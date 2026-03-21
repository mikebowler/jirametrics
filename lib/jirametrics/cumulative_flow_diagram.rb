# frozen_string_literal: true

require 'jirametrics/cfd_data_builder'

class CumulativeFlowDiagram < ChartBase
  # Used to embed a Chart.js segment callback (which contains JS functions) into
  # a JSON-like dataset object. The custom to_json emits raw JS rather than a
  # quoted string, following the same pattern as ExpeditedChart::EXPEDITED_SEGMENT.
  class Segment
    def initialize windows
      # Build a JS array literal of [start_date, end_date] string pairs
      @windows_js = windows
        .map { |w| "[#{w[:start_date].to_json}, #{w[:end_date].to_json}]" }
        .join(', ')
    end

    def to_json *_args
      <<~JS
        {
          borderDash: function(ctx) {
            const x = ctx.p1.parsed.x;
            const windows = [#{@windows_js}];
            return windows.some(function(w) {
              return x >= new Date(w[0]).getTime() && x <= new Date(w[1]).getTime();
            }) ? [6, 4] : undefined;
          }
        }
      JS
    end
  end
  private_constant :Segment

  class CfdColumnRules < Rules
    attr_accessor :color, :label, :label_hint
  end
  private_constant :CfdColumnRules

  def initialize block
    super()
    header_text 'Cumulative Flow Diagram'
    description_text <<~HTML
      <div class="p">
        A Cumulative Flow Diagram (CFD) shows how work accumulates across board columns over time.
        Each coloured band represents a workflow stage. The top edge of the leftmost band shows
        total work entered; the top edge of the rightmost band shows total work completed.
      </div>
      <div class="p">
        A widening band means work is piling up in that stage — a bottleneck. Parallel top edges
        (bands staying the same width) indicate smooth flow. Steep rises in the leftmost band
        without corresponding rises on the right mean new work is arriving faster than it is
        being finished.
      </div>
      <div class="p">
        Dashed lines and hatched regions indicate periods where an item moved backwards through
        the workflow (a correction). These highlight rework or process irregularities worth
        investigating.
      </div>
    HTML
    instance_eval(&block)
  end

  def column_rules &block
    @column_rules_block = block
  end

  def run
    all_columns = current_board.visible_columns

    column_rules_list = all_columns.map do |column|
      rules = CfdColumnRules.new
      @column_rules_block&.call(column, rules)
      rules
    end

    active_pairs   = all_columns.zip(column_rules_list).reject { |_, rules| rules.ignored? }
    active_columns = active_pairs.map(&:first)
    active_rules   = active_pairs.map(&:last)

    cfd = CfdDataBuilder.new(
      board: current_board,
      issues: issues,
      date_range: date_range,
      columns: active_columns
    ).run

    columns            = cfd[:columns]
    daily_counts       = cfd[:daily_counts]
    correction_windows = cfd[:correction_windows]
    column_count       = columns.size

    # Convert cumulative totals to marginal band heights for Chart.js stacking.
    # cumulative[i] = issues that reached column i or further.
    # marginal[i]   = cumulative[i] - cumulative[i+1]  (last column: marginal = cumulative)
    daily_marginals = daily_counts.transform_values do |cumulative|
      cumulative.each_with_index.map do |count, i|
        i < column_count - 1 ? count - cumulative[i + 1] : count
      end
    end

    border_colors = active_rules.map { |rules| rules.color || random_color }

    fill_colors = active_rules.zip(border_colors).map { |rules, border| fill_color_for(rules, border) }

    # Datasets in reversed order: rightmost column first (bottom of stack), leftmost last (top).
    data_sets = columns.each_with_index.map do |name, col_index|
      col_windows = correction_windows
        .select { |w| w[:column_index] == col_index }
        .map { |w| { start_date: w[:start_date].to_s, end_date: w[:end_date].to_s } }

      {
        label: active_rules[col_index].label || name,
        label_hint: active_rules[col_index].label_hint,
        data: date_range.map { |date| { x: date.to_s, y: daily_marginals[date][col_index] } },
        backgroundColor: fill_colors[col_index],
        borderColor: border_colors[col_index],
        fill: true,
        tension: 0,
        segment: Segment.new(col_windows)
      }
    end.reverse

    # Correction windows for the afterDraw hatch plugin, with dataset index in
    # Chart.js dataset array (reversed: done column = index 0).
    hatch_windows = correction_windows.map do |w|
      {
        dataset_index: column_count - 1 - w[:column_index],
        start_date: w[:start_date].to_s,
        end_date: w[:end_date].to_s,
        color: border_colors[w[:column_index]]
      }
    end

    wrap_and_render(binding, __FILE__)
  end

  private

  def hex_to_rgba hex, alpha
    r, g, b = hex.delete_prefix('#').scan(/../).map { |c| c.to_i(16) }
    "rgba(#{r}, #{g}, #{b}, #{alpha})"
  end

  def fill_color_for rules, border
    if rules.color.nil? || rules.color.match?(/\A#[0-9a-fA-F]{6}\z/)
      hex_to_rgba(border, 0.35)
    else
      rules.color
    end
  end
end
