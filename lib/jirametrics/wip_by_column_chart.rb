# frozen_string_literal: true

require 'jirametrics/chart_base'

class WipByColumnChart < ChartBase
  attr_accessor :possible_statuses, :board_id

  ColumnStats = Struct.new(:name, :min_wip_limit, :max_wip_limit, :wip_history, keyword_init: true)

  def initialize block
    super()
    header_text 'WIP by column'
    description_text <<-HTML
      <p>
        This chart shows how much time each board column has spent at different WIP (Work in Progress) levels.
      </p>
      <p>
        Each row on the Y axis is a WIP level (the number of items in that column at the same time).
        Each column on the X axis is a board column.
        The horizontal bars show what percentage of the total time that column spent at that WIP level —
        a wider bar means more time was spent there.
      </p>
      <p>
        A column whose widest bar is at WIP&nbsp;1 was almost always working on one item at a time, often called
        single-piece-flow. This team is likely collaborating very well and might have been
        <a href="https://blog.mikebowler.ca/2021/06/19/pair-programming/">pairing</a> or
        <a href="https://blog.mikebowler.ca/2023/04/22/ensemble-programming/">mobbing/ensembling</a>
        and these teams tend to be very effective.
      </p>
      <p>
        A column with wide bars at high WIP levels usually indicates a team that is highly siloed. Where each person
        is working by themselves.
      </p>
      <p>
        The dashed lines show the minimum and maximum WIP limits configured on the board.
        If the widest bar sits well above the maximum limit, the limit may be set too low or not being respected.
        If the widest bar sits below the minimum limit, consider whether that limit is still meaningful.
      </p>
      <p>
        Hover over any bar to see the exact percentage.
      </p>
      <% if @all_boards[@board_id].team_managed_kanban? %>
        <p>
          If the data looks a bit off then that's probably because you're using a Team Managed project in "kanban mode".
          For this specific case, we are unable to tell if an item is actually visible on the board and so we may
          be reporting more items started than you actually see on the board. See
          <a href="https://jirametrics.org/faq/#team-managed-kanban-backlog">the FAQ</a>.
        </p>
      <% end %>
    HTML

    instance_eval(&block)
  end

  def show_recommendations
    @show_recommendations = true
  end

  def run
    @header_text += " on board: #{current_board.name}"
    stats = column_stats
    @column_names = stats.collect(&:name)
    @wip_data = stats.collect do |stat|
      total = stat.wip_history.sum { |_wip, seconds| seconds }.to_f
      next [] if total.zero?

      stat.wip_history.collect { |wip, seconds| { 'wip' => wip, 'pct' => format_pct(seconds, total) } }
    end
    @max_wip = stats.flat_map { |s| s.wip_history.collect { |wip, _| wip } }.max || 0
    @wip_limits = stats.collect { |s| { 'min' => s.min_wip_limit, 'max' => s.max_wip_limit } }
    @recommendations = @show_recommendations ? compute_recommendations(stats) : Array.new(stats.size)

    trim_zero_end_columns
    @recommendation_texts = @show_recommendations ? build_recommendation_texts : []

    wrap_and_render(binding, __FILE__)
  end

  def column_stats
    board = current_board
    columns = board.visible_columns
    status_to_column = build_status_to_column_map(columns)
    relevant_issues = @issues.select { |issue| issue.board.id == @board_id }

    current_column = initial_column_state(relevant_issues, status_to_column)
    events = events_within_range(relevant_issues, status_to_column)
    column_wip_seconds = compute_wip_seconds(columns, current_column, events)

    columns.collect.with_index do |column, index|
      ColumnStats.new(
        name: column.name,
        min_wip_limit: column.min,
        max_wip_limit: column.max,
        wip_history: column_wip_seconds[index].sort.to_a
      )
    end
  end

  private

  def trim_zero_end_columns
    all_zero = @wip_data.map { |col| col.none? { |e| e['wip'].positive? } }
    first = all_zero.index(false)
    return unless first

    last = all_zero.rindex(false)
    @column_names    = @column_names[first..last]
    @wip_data        = @wip_data[first..last]
    @wip_limits      = @wip_limits[first..last]
    @recommendations = @recommendations[first..last]
    @max_wip         = @wip_data.flat_map { |col| col.map { |e| e['wip'] } }.max || 0
  end

  def compute_recommendations stats
    stats.collect do |stat|
      next nil if stat.wip_history.empty?

      total = stat.wip_history.sum { |_wip, seconds| seconds }.to_f
      next nil if total.zero?

      cumulative = 0
      stat.wip_history.sort.find do |_wip, seconds|
        cumulative += seconds
        cumulative / total >= 0.85
      end&.first
    end
  end

  def build_recommendation_texts
    @column_names.each_with_index.filter_map do |name, i|
      rec = @recommendations[i]
      next if rec.nil?

      next "Almost nothing passes through column '#{name}'. Do we still need it?" if rec.zero?

      max = @wip_limits[i]['max']
      if max.nil?
        "Add a WIP limit to column '#{name}' — suggested maximum: #{rec}"
      elsif rec < max
        "Lower the WIP limit for '#{name}' from #{max} to #{rec}"
      elsif rec > max
        "Raise the WIP limit for '#{name}' from #{max} to #{rec}"
      end
    end
  end

  def format_pct seconds, total
    raw = seconds / total * 100.0
    (1..10).each do |decimals|
      rounded = raw.round(decimals)
      next if rounded.zero? && raw.positive?
      next if rounded >= 100.0 && raw < 100.0

      return rounded
    end
    raw
  end

  def build_status_to_column_map columns
    columns.each_with_object({}).with_index do |(column, map), index|
      column.status_ids.each { |id| map[id] = index }
    end
  end

  def initial_column_state relevant_issues, status_to_column
    relevant_issues.each_with_object({}) do |issue, hash|
      started_time, stopped_time = issue.board.cycletime.started_stopped_times(issue)
      in_wip = started_time &&
               started_time <= time_range.begin &&
               (stopped_time.nil? || stopped_time > time_range.begin)
      unless in_wip
        hash[issue] = nil
        next
      end

      last_change = issue.status_changes.reverse.find { |c| c.time <= time_range.begin }
      hash[issue] = last_change ? status_to_column[last_change.value_id] : nil
    end
  end

  def events_within_range relevant_issues, status_to_column
    events = []
    relevant_issues.each do |issue|
      started_time, stopped_time = issue.board.cycletime.started_stopped_times(issue)
      next unless started_time

      # Issue starts within the window: add an explicit event to enter WIP in its current column
      if started_time > time_range.begin && started_time <= time_range.end
        last_change = issue.status_changes.reverse.find { |c| c.time <= started_time }
        events << [started_time, issue, last_change ? status_to_column[last_change.value_id] : nil]
      end

      # Status changes while the issue is actively in WIP and within the window
      issue.status_changes.each do |change|
        next unless change.time > time_range.begin
        next if change.time > time_range.end
        next unless change.time >= started_time
        next if stopped_time && change.time >= stopped_time

        events << [change.time, issue, status_to_column[change.value_id]]
      end

      # Issue stops within the window: add an explicit event to exit WIP
      if stopped_time && stopped_time > time_range.begin && stopped_time <= time_range.end
        events << [stopped_time, issue, nil]
      end
    end
    events.sort_by!(&:first)
  end

  def compute_wip_seconds columns, current_column, events
    wip_counts = Array.new(columns.size, 0)
    current_column.each_value { |col| wip_counts[col] += 1 unless col.nil? }

    column_wip_seconds = Array.new(columns.size) { Hash.new(0) }
    prev_time = time_range.begin

    events.each do |time, issue, new_col|
      elapsed = (time - prev_time).to_i
      if elapsed.positive?
        wip_counts.each_with_index { |wip, idx| column_wip_seconds[idx][wip] += elapsed }
        prev_time = time
      end

      old_col = current_column[issue]
      wip_counts[old_col] -= 1 unless old_col.nil?
      wip_counts[new_col] += 1 unless new_col.nil?
      current_column[issue] = new_col
    end

    elapsed = (time_range.end - prev_time).to_i
    wip_counts.each_with_index { |wip, idx| column_wip_seconds[idx][wip] += elapsed } if elapsed.positive?

    column_wip_seconds
  end
end
