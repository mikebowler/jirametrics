# frozen_string_literal: true

require 'jirametrics/percentile_validation'

class FlowEfficiencyScatterplot < ChartBase
  include PercentileValidation

  # The width of one histogram bar, in percentage points. Deliberately not configurable: bucket
  # boundaries can be moved to create or flatten a spike, so we pick one round number and leave it
  # alone whatever the data looks like.
  BUCKET_SIZE = 5

  # Items at or above this are reported as spending more than half their life being worked on.
  # Almost always that means blocked and stalled time isn't being recorded rather than genuinely
  # excellent flow, so the chart says so rather than letting it read as a good result.
  BAND_FLOOR = 50

  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text 'Flow Efficiency'
    description_text <<-HTML
      <div class="p">
        This chart shows what proportion of each work item's life was actually spent adding value.
        <a href="https://blog.mikebowler.ca/2024/07/06/flow-efficiency/">Flow efficiency</a> is that
        ratio.
      </div>
      <div class="p">
        <math>
          <mn>Flow efficiency (%)</mn>
          <mo>=</mo>
          <mfrac>
            <mrow><mn>Time adding value</mn></mrow>
            <mrow><mn>Total time</mn></mrow>
          </mfrac>
        </math>
      </div>
      <div class="p">
        This is a claim about the work item, not about how hard anyone worked. An item can sit
        untouched for weeks while every person on the team is flat out on something else. That
        distinction, between flow efficiency and
        <a href="https://blog.mikebowler.ca/2023/05/20/busyness/">keeping our people busy</a>, is the
        whole point: the two are different measures and improving one often makes the other worse.
      </div>
      <div style="border: 1px solid gray; padding: 0.2em">
        Every gap in recording blocked and stalled time makes this chart look <b>better</b> than
        reality, never worse. So a low number here is trustworthy. A high one is more likely to mean
        you aren't capturing your waiting time than that your flow is excellent.
        <%= band_warning %>
      </div>
    HTML

    @percentiles = [50, 85]

    instance_eval(&block)
  end

  # Which percentiles to draw as vertical lines. An empty list drops them.
  def percentiles list = nil
    @percentiles = validate_percentiles(list) unless list.nil?
    @percentiles
  end

  def run
    efficiencies = flow_efficiencies_for completed_issues_in_range(include_unstarted: false)

    if efficiencies.empty?
      return "<h1 class='foldable'>#{@header_text}</h1>" \
        '<div>No data matched the selected criteria. Nothing to show.</div>'
    end

    @item_count = efficiencies.size
    @buckets = histogram_buckets efficiencies
    @percentile_markers = percentile_markers_for efficiencies
    @median = percentile_of efficiencies, 50
    @above_band = efficiencies.count { |efficiency| efficiency >= BAND_FLOOR }

    wrap_and_render(binding, __FILE__)
  end

  # One flow efficiency percentage per completed item.
  def flow_efficiencies_for issues
    issues.collect do |issue|
      active_time, total_time = issue.flow_efficiency_numbers end_time: time_range.end, settings: settings
      efficiency = active_time * 100.0 / total_time
      next efficiency unless efficiency.nan?

      # Seen in production on a misconfigured board. Nothing to divide by, so nothing to report.
      file_system.log(
        "Issue(#{issue.key}) flow_efficiency: NaN, active_time: #{active_time}, total_time: #{total_time}"
      )
      0.0
    end
  end

  # One bar per BUCKET_SIZE band, plotted at the band's centre on a linear axis so each bar
  # physically spans the range it counts rather than sitting centred on a tick.
  def histogram_buckets efficiencies
    (0...100).step(BUCKET_SIZE).collect do |low|
      high = low + BUCKET_SIZE
      { 'x' => low + (BUCKET_SIZE / 2.0), 'y' => efficiencies.count { |value| in_band? value, low, high } }
    end
  end

  # 100 is the only value that can sit exactly on a band's upper edge, so the top band has to take
  # it. An exclusive comparison everywhere would silently drop the one item a reader looks for first.
  def in_band? value, low, high
    value >= low && (value < high || (high == 100 && value <= 100))
  end

  # The label is built here rather than in the template because it's the sentence doing the
  # persuading, and it's phrased to avoid ordinals so that any configured percentile reads properly.
  def percentile_markers_for efficiencies
    @percentiles.collect do |percentile|
      value = percentile_of efficiencies, percentile
      {
        'percentile' => percentile,
        'value' => value,
        'label' => "#{percentile}% of items are below #{value.round 1}%"
      }
    end
  end

  # Only says anything when items actually land above BAND_FLOOR, because that's the case where the
  # chart would otherwise read as praise.
  def band_warning
    return '' if @above_band.to_i.zero?

    subject, possessive =
      if @above_band == 1
        ['One of your work items reports', 'its']
      else
        ["#{@above_band} of your work items report", 'their']
      end

    "<div class=\"p\">#{subject} spending more than #{BAND_FLOOR}% of #{possessive} life being " \
      'actively worked on. That is far more likely to mean the blocked and stalled time was never ' \
      'recorded than that the flow was genuinely that good.</div>'
  end
end
