# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe CycletimeScatterplot do
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.time_range = to_time('2020-01-01')..to_time('2020-02-01')
    end
  end

  describe '#percentiles' do
    it 'defaults to the 85th' do
      expect(chart.percentiles).to eq [85]
    end

    it 'accepts a replacement list' do
      chart.percentiles [50, 85, 98]
      expect(chart.percentiles).to eq [50, 85, 98]
    end

    it 'accepts an empty list to switch all lines off' do
      chart.percentiles []
      expect(chart.percentiles).to eq []
    end

    it 'rejects values outside 0..100' do
      expect { chart.percentiles [50, 150] }.to raise_error(
        ArgumentError, /percentile 150 must be between 0 and 100/
      )
    end

    it 'rejects non-integers' do
      expect { chart.percentiles [85.5] }.to raise_error(
        ArgumentError, /percentile 85.5 must be an integer/
      )
    end

    it 'removes duplicates and sorts' do
      chart.percentiles [98, 50, 98]
      expect(chart.percentiles).to eq [50, 98]
    end
  end

  describe '#cycletime_unit' do
    it 'accepts :days (the only supported unit)' do
      expect { chart.cycletime_unit :days }.not_to raise_error
    end

    it 'raises NotImplementedError for any other unit' do
      expect { chart.cycletime_unit :hours }.to raise_error(
        NotImplementedError, /CycletimeScatterplot only supports :days/
      )
    end
  end

  describe '#data_for_issue' do
    it 'gets data' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.data_for_issue issue).to eq({
        title: ['SP-10 : Check in people at an event (81 days)'],
        x: chart_format(issue.last_resolution.time),
        y: 81
      })
    end

    it 'appends issue_hint when set' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue => '(priority: high)' }
      expect(chart.data_for_issue(issue)[:title])
        .to eq ['SP-10 : Check in people at an event (81 days) (priority: high)']
    end
  end

  describe '#label_days' do
    it 'returns singular for 1' do
      expect(chart.label_days 1).to eq '1 day'
    end

    it 'returns singular for 0' do
      expect(chart.label_days 0).to eq '0 days'
    end
  end

  it 'creates datasets' do
    board = load_complete_sample_board
    issue = load_issue('SP-10', board: board)

    board.cycletime = default_cycletime_config
    chart.issues = [issue]

    expect(chart.create_datasets [issue]).to eq([
      {
        backgroundColor: CssVariable['--type-story-color'],
        data: [
          {
            title: ['SP-10 : Check in people at an event (81 days)'],
            x: chart_format(issue.last_resolution.time),
            y: 81
         }
        ],
        fill: false,
        label: 'Story (85% at 81 days)',
        showLine: false
      },
      {
        type: 'line',
        label: 'Story Trendline',
        data: [],
        fill: false,
        borderWidth: 1,
        markerType: 'none',
        borderColor: CssVariable['--type-story-color'],
        borderDash: [6, 3],
        pointStyle: 'dash',
        hidden: true
      }
     ])
  end

  describe 'percentage lines' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-10', board: board) }

    before do
      board.cycletime = default_cycletime_config
      chart.issues = [issue]
    end

    it 'labels a single percentile exactly as it always has' do
      expect(chart.create_datasets([issue]).first[:label]).to eq 'Story (85% at 81 days)'
    end

    it 'lists every configured percentile in the label' do
      chart.percentiles [50, 85]
      expect(chart.create_datasets([issue]).first[:label])
        .to eq 'Story (50% at 81 days, 85% at 81 days)'
    end

    it 'omits the parenthetical when the group has no percentiles' do
      chart.grouping_rules do |_issue, rule|
        rule.label = 'Story'
        rule.percentiles = []
      end
      expect(chart.create_datasets([issue]).first[:label]).to eq 'Story'
    end

    it 'lets a group override the chart default' do
      chart.percentiles [85]
      chart.grouping_rules do |_issue, rule|
        rule.label = 'Story'
        rule.percentiles = [50]
      end
      chart.create_datasets [issue]
      expect(chart.percentage_lines.collect { |line| line[:percentile] }).to eq [50]
    end

    it "carries each group's name so the hover label can say which line it is" do
      chart.percentiles [85]
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2022-12-31')
      chart.issues = [issue]
      allow(chart).to receive(:wrap_and_render).and_return('')
      chart.run

      # The overall line has no legend entry of its own, so without a name there is nothing at all
      # to identify it when hovering. "All items" matches the wording already used in the
      # description prose and excludes anything a grouping rule ignored.
      aggregate_failures do
        expect(chart.percentage_lines.collect { |line| line[:label] }).to eq ['Story', 'All items']
      end
    end

    # Every other example overrides at most one group. This pins the case where all three levels
    # carry a different NUMBER of percentiles at once, since each group resolves independently and
    # the annotation ids have to stay distinct across groups of differing size.
    it 'gives each group its own count of lines while the overall keeps the chart default' do
      second_issue = load_issue 'SP-14', board: board
      chart.percentiles [85]
      # Wide enough to cover both fixtures: SP-10 resolves 2021-09-06 and SP-14 resolves 2022-04-19.
      # Too narrow a range drops an issue and quietly turns this into a one-group test.
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2022-12-31')
      chart.issues = [issue, second_issue]
      chart.grouping_rules do |grouped_issue, rule|
        if grouped_issue.key == 'SP-10'
          rule.label = 'Story'
          rule.percentiles = [85, 50] # out of order on purpose; the setter sorts it
        else
          rule.label = 'Bug'
          rule.percentiles = [50, 85, 95]
        end
      end
      allow(chart).to receive(:wrap_and_render).and_return('')
      chart.run

      aggregate_failures do
        expect(chart.percentage_lines.collect { |line| line[:id] })
          .to eq %w[group0_50 group0_85 group1_50 group1_85 group1_95 overall_85]
        expect(chart.legend_annotation_map)
          .to eq({ 0 => %w[group0_50 group0_85], 2 => %w[group1_50 group1_85 group1_95] })
      end
    end
  end

  describe '#legend_annotation_map' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-10', board: board) }

    before do
      board.cycletime = default_cycletime_config
      chart.issues = [issue]
    end

    it "maps a dataset index to that group's own annotation ids" do
      chart.percentiles [50, 85]
      chart.create_datasets [issue]
      expect(chart.legend_annotation_map).to eq({ 0 => %w[group0_50 group0_85] })
    end

    it 'keeps two groups apart even when they share a label' do
      # eql? compares label AND colour, so this is two groups, not one. Keying the map by label
      # would merge them and one legend click would toggle both groups' lines.
      other_issue = load_issue('SP-14', board: board)
      chart.grouping_rules do |grouped_issue, rule|
        rule.label = 'Story'
        rule.color = grouped_issue.key == 'SP-10' ? 'blue' : 'green'
      end
      chart.create_datasets [issue, other_issue]
      expect(chart.legend_annotation_map).to eq({ 0 => %w[group0_85], 2 => %w[group1_85] })
    end

    it 'excludes overall lines so they survive a group toggle' do
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2021-12-31')
      allow(chart).to receive(:wrap_and_render).and_return('')
      chart.run

      aggregate_failures do
        # The overall line must actually exist in this run, otherwise the second expectation
        # below is vacuously true.
        expect(chart.percentage_lines.collect { |line| line[:id] }).to include 'overall_85'
        expect(chart.legend_annotation_map.values.flatten).not_to include 'overall_85'
        expect(chart.legend_annotation_map[0]).to include 'group0_85'
      end
    end
  end

  describe '#percentile_description' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-10', board: board) }

    before do
      board.cycletime = default_cycletime_config
      chart.issues = [issue]
      chart.date_range = Date.parse('2021-01-01')..Date.parse('2021-12-31')
      allow(chart).to receive(:wrap_and_render).and_return('')
    end

    it 'describes a single percentile with its complement' do
      chart.percentiles [85]
      chart.run
      aggregate_failures do
        expect(chart.percentile_description).to include '85th percentile'
        expect(chart.percentile_description).to include 'remaining 15%'
      end
    end

    it 'describes several percentiles without the singular framing' do
      chart.percentiles [50, 85]
      chart.run
      aggregate_failures do
        expect(chart.percentile_description).to include '50th'
        expect(chart.percentile_description).to include '85th'
        expect(chart.percentile_description).not_to include 'reasonable proxy'
      end
    end

    it 'says nothing when the lines are switched off' do
      chart.percentiles []
      chart.grouping_rules do |_issue, rule|
        rule.label = 'Story'
        rule.percentiles = [85]
      end
      chart.run
      aggregate_failures do
        # The group still draws its own lines, so an empty data set can't be the thing making
        # the description empty. Only the overall lines were switched off.
        expect(chart.percentage_lines).not_to be_empty
        expect(chart.percentile_description).to eq ''
      end
    end

    it 'renders the configured percentiles into description_text at render time' do
      # Regression guard for the ERB tag on description_text: it must be <%= percentile_description %>
      # (render time, against run's binding) and not #{percentile_description} (construction time,
      # before the config block below has set percentiles). If someone "simplifies" that tag back to
      # interpolation, description_text is built during initialize, before chart.percentiles [50, 85]
      # below ever runs, so it would silently describe the default [85] instead.
      chart.percentiles [50, 85]
      chart.run
      rendered = ERB.new(chart.description_text).result(chart.instance_eval { binding })
      expect(rendered).to include '50th'
    end
  end

  describe '#group_issues' do
    let(:board) { load_complete_sample_board }
    let(:issue1) { load_issue 'SP-1', board: board }

    it 'renders when no rules specified' do
      expected_rules = GroupingRules.new
      expected_rules.color = '--type-story-color'
      expected_rules.label = issue1.type
      expect(chart.group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end
  end

  describe '#x_value' do
    it 'returns the stop time from cycletime' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.x_value(issue)).to eq issue.last_resolution.time
    end
  end

  describe '#y_value' do
    it 'returns the cycletime in days' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.y_value(issue)).to eq 81
    end
  end

  describe '#title_value' do
    it 'formats key, summary, and cycletime' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      expect(chart.title_value(issue)).to eq 'SP-10 : Check in people at an event (81 days)'
    end

    it 'appends hint when set' do
      board = load_complete_sample_board
      issue = load_issue('SP-10', board: board)
      board.cycletime = default_cycletime_config
      chart.issue_hints = { issue => '(priority: high)' }
      expect(chart.title_value(issue)).to eq 'SP-10 : Check in people at an event (81 days) (priority: high)'
    end
  end

  describe '#cap_y_axis' do
    it 'is disabled by default' do
      expect(chart.y_axis_cap_percentile).to be_nil
    end

    it 'defaults to the 98th percentile when enabled with no argument' do
      chart.cap_y_axis
      expect(chart.y_axis_cap_percentile).to eq 98
    end

    it 'accepts an explicit percentile' do
      chart.cap_y_axis percentile: 90
      expect(chart.y_axis_cap_percentile).to eq 90
    end
  end

  describe '#percentile_value' do
    it 'returns the value at the requested percentile, min-filtered' do
      items = Array.new(20) { |index| "item#{index}" }
      values = (1..19).to_a + [500] # 20 values; index 20*85/100 = 17 -> sorted[17] = 18
      allow(chart).to receive(:y_value) { |item| values[items.index(item)] }
      expect(chart.percentile_value(items, 85)).to eq 18
    end
  end

  describe '#percentile_lines_for' do
    let(:board) { load_complete_sample_board }
    let(:issues) { %w[SP-10 SP-14].map { |key| load_issue(key, board: board) } }

    before { board.cycletime = default_cycletime_config }

    it 'returns a pair per requested percentile' do
      result = chart.percentile_lines_for(issues, [50, 85])
      expect(result.collect(&:first)).to eq [50, 85]
    end

    it 'pairs each percentile with its value' do
      expect(chart.percentile_lines_for(issues, [85]))
        .to eq [[85, chart.percentile_value(issues, 85)]]
    end

    it 'returns nothing for an empty list' do
      expect(chart.percentile_lines_for(issues, [])).to be_empty
    end

    it 'drops percentiles that have no value' do
      expect(chart.percentile_lines_for([], [85])).to be_empty
    end

    it 'sorts unsorted input ascending by percentile' do
      expect(chart.percentile_lines_for(issues, [98, 50]).collect(&:first)).to eq [50, 98]
    end
  end

  describe '#compute_cap' do
    let(:items) { Array.new(20) { |index| "item#{index}" } }
    let(:values) { (1..19).to_a + [500] }

    before { allow(chart).to receive(:y_value) { |item| values[items.index(item)] } }

    it 'returns nil when capping is disabled' do
      expect(chart.compute_cap(items)).to be_nil
    end

    it 'returns nil when nothing exceeds the cutoff' do
      chart.cap_y_axis percentile: 100
      expect(chart.compute_cap(items)).to be_nil
    end

    it 'computes the cap layout from the full set' do
      chart.cap_y_axis percentile: 85 # cutoff = 18; values 19 and 500 exceed it
      cap = chart.compute_cap(items)
      aggregate_failures do
        expect(cap[:cutoff]).to eq 18
        expect(cap[:outlier_count]).to eq 2
        expect(cap[:sep]).to be_within(0.001).of(18 + (18 * 0.06))
        expect(cap[:axis_max]).to eq (18 + (18 * 0.06) + (18 * 0.15)).ceil
        expect(cap[:pin_row]).to be_within(0.001).of((18 + (18 * 0.06)) + (18 * 0.15 * 0.55))
      end
    end

    it 'pluralizes and rounds the label for a single outlier' do
      chart.cap_y_axis percentile: 85 # cutoff = 18; values 19 and 500 exceed it
      cap = chart.compute_cap(items)
      expect(cap[:label]).to eq '2 items above 18 days'
    end

    it 'uses the singular word and rounds a fractional cutoff for exactly one outlier' do
      fractional_values = (1..18).to_a + [18.4, 500] # 20 values; percentile 90 -> cutoff = 18.4
      allow(chart).to receive(:y_value) { |item| fractional_values[items.index(item)] }
      chart.cap_y_axis percentile: 90
      cap = chart.compute_cap(items)
      aggregate_failures do
        expect(cap[:outlier_count]).to eq 1
        expect(cap[:label]).to eq '1 item above 18 days'
      end
    end
  end

  describe 'capping in create_datasets' do
    let(:board) { load_complete_sample_board }
    let(:issue) { load_issue('SP-10', board: board) }

    before { board.cycletime = default_cycletime_config }

    it 'leaves points unchanged when capping is disabled' do
      point = chart.create_datasets([issue]).first[:data].first
      aggregate_failures do
        expect(point[:y]).to eq 81
        expect(point).not_to have_key(:over)
      end
    end

    it 'remaps an over-cap point to the pinned row and flags it' do
      # SP-10 (81 days) and SP-14 (78 days). Percentile 1 on this pair makes 78 the cutoff,
      # so SP-10's 81 lands strictly above it and gets remapped.
      other_issue = load_issue('SP-14', board: board)
      the_items = [issue, other_issue]
      chart.cap_y_axis percentile: 1
      scatter = chart.create_datasets(the_items).first
      sp10_title = ['SP-10 : Check in people at an event (81 days)']
      point = scatter[:data].find { |data_point| data_point[:title] == sp10_title }
      cap = chart.compute_cap(the_items)
      aggregate_failures do
        expect(point[:over]).to be true
        expect(point[:y]).to eq cap[:pin_row]
        expect(point[:title]).to eq ['SP-10 : Check in people at an event (81 days)']
      end
    end
  end

  describe 'statistics are unaffected by capping' do
    let(:board) { load_complete_sample_board }
    let(:issues) { %w[SP-10 SP-14].map { |key| load_issue(key, board: board) } }

    before { board.cycletime = default_cycletime_config }

    it 'computes the same 85% line with capping on and off' do
      uncapped = chart.percentile_value(issues, 85)
      chart.cap_y_axis percentile: 90
      capped = chart.percentile_value(issues, 85)
      expect(capped).to eq uncapped
    end
  end

  describe 'trend line regression is unaffected by capping' do
    let(:board) { load_complete_sample_board }
    # SP-10 (81 days) and SP-14 (78 days) sit close together; SP-13 (306 days) is a large
    # outlier. Percentile 60 on this trio puts the cutoff at 81, so only SP-13 gets capped.
    let(:issues) { %w[SP-10 SP-14 SP-13].map { |key| load_issue(key, board: board) } }

    before do
      board.cycletime = default_cycletime_config
      chart.time_range = to_time('2021-01-01')..to_time('2022-12-31')
    end

    def trend_line_slope data_sets
      trend_data = data_sets.find { |data_set| data_set[:type] == 'line' }[:data]
      x1 = Time.parse(trend_data[0][:x]).to_i
      y1 = trend_data[0][:y]
      x2 = Time.parse(trend_data[1][:x]).to_i
      y2 = trend_data[1][:y]
      (y2 - y1).to_f / (x2 - x1)
    end

    it 'fits the same regression slope whether capping is on or off' do
      uncapped_slope = trend_line_slope(chart.create_datasets(issues))

      chart.cap_y_axis percentile: 60
      capped_slope = trend_line_slope(chart.create_datasets(issues))

      expect(capped_slope).to be_within(0.0000001).of(uncapped_slope)
    end

    it 'records the true cycletime on a capped point, separate from the pinned y' do
      chart.cap_y_axis percentile: 60
      scatter = chart.create_datasets(issues).first
      sp13_title = ['SP-13 : Report of people checked in at an event (306 days)']
      point = scatter[:data].find { |data_point| data_point[:title] == sp13_title }
      cap = chart.compute_cap(issues)
      aggregate_failures do
        expect(point[:over]).to be true
        expect(point[:y]).to eq cap[:pin_row]
        expect(point[:true_y]).to eq 306
      end
    end
  end

  describe '#group_issues percentile conflicts' do
    let(:board) { load_complete_sample_board }
    let(:issues) { %w[SP-10 SP-14].map { |key| load_issue(key, board: board) } }

    before { board.cycletime = default_cycletime_config }

    it 'raises when one group is given two different percentile lists' do
      chart.grouping_rules do |issue, rule|
        rule.label = 'Everything'
        rule.percentiles = issue.key == 'SP-10' ? [50] : [98]
      end
      expect { chart.group_issues issues }.to raise_error(
        ArgumentError, /group "Everything" was given conflicting percentiles: \[50\] and \[98\]/
      )
    end

    it 'allows the same list to be set repeatedly' do
      chart.grouping_rules do |_issue, rule|
        rule.label = 'Everything'
        rule.percentiles = [50]
      end
      expect { chart.group_issues issues }.not_to raise_error
    end

    it 'never reconciles percentiles across different groups' do
      chart.grouping_rules do |issue, rule|
        if issue.key == 'SP-10'
          rule.label = 'Group A'
          rule.percentiles = [50]
        else
          rule.label = 'Group B'
        end
      end
      result = chart.group_issues issues
      group_a = result.keys.find { |rule| rule.label == 'Group A' }
      group_b = result.keys.find { |rule| rule.label == 'Group B' }
      aggregate_failures do
        expect(result.size).to eq 2
        expect(group_a.percentiles).to eq [50]
        expect(group_b.percentiles).to be_nil
      end
    end

    it 'reconciles to the same percentiles regardless of arrival order' do
      chart.grouping_rules do |issue, rule|
        rule.label = 'Everything'
        rule.percentiles = [50] if issue.key == 'SP-14'
      end
      nil_arriving_first = chart.group_issues issues
      value_arriving_first = chart.group_issues issues.reverse
      aggregate_failures do
        expect(nil_arriving_first.keys.first.percentiles).to eq [50]
        expect(value_arriving_first.keys.first.percentiles).to eq [50]
      end
    end
  end
end
