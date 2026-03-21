# Cumulative Flow Diagram Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `CumulativeFlowDiagram` chart and supporting `CfdDataBuilder` computation class to jirametrics.

**Architecture:** `CfdDataBuilder` (pure computation, no chart infrastructure) computes per-column daily cumulative counts and correction windows from the high-water-mark algorithm. `CumulativeFlowDiagram < ChartBase` is a thin rendering class that calls the builder and passes results to an ERB template producing a Chart.js stacked area chart.

**Tech Stack:** Ruby, RSpec, Chart.js (stacked line chart with custom `segment` callback and `afterDraw` plugin for backwards-movement visualization), ERB templates.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/jirametrics/cfd_data_builder.rb` | Create | Pure computation class |
| `spec/cfd_data_builder_spec.rb` | Create | Unit tests for computation |
| `lib/jirametrics/cumulative_flow_diagram.rb` | Create | Chart rendering class |
| `lib/jirametrics/html/cumulative_flow_diagram.erb` | Create | Chart.js stacked area template |
| `spec/cumulative_flow_diagram_spec.rb` | Create | Integration chart spec |

No changes to `lib/jirametrics.rb` — `require_rel 'jirametrics'` auto-loads all files in the directory.

---

## Background: Key Codebase Facts

**`sample_board` visible columns** (from `spec/testdata/sample_board_1_configuration.json`, kanban board drops the first "Backlog" column):
- Index 0: Ready (status_ids: [10001])
- Index 1: In Progress (status_ids: [3])
- Index 2: Review (status_ids: [10011])
- Index 3: Done (status_ids: [10002])

**Test helpers** (from `spec/spec_helper.rb`):
- `sample_board` — loads the test board fixture
- `empty_issue(created:, board:, key:)` — creates an issue with no changes
- `add_mock_change(issue:, field:, value:, value_id:, time:)` — adds a `ChangeItem` to `issue.changes`
- For status changes: always pass `field: 'status'` AND `value_id:` (integer status ID). `value_id` must be an integer (e.g., `10001`, not `'10001'`).
- `issue.status_changes` — returns only changes where `field == 'status'`; `change.value_id` is already an integer

**Chart patterns** (from `expedited_chart.rb` and `aging_work_in_progress_chart_spec.rb`):
- Chart class: `class Foo < ChartBase`, `super()`, then `instance_eval(&block)` in initialize
- `run` method ends with `wrap_and_render(binding, __FILE__)`
- Chart spec setup: `chart.board_id = 1`, `chart.all_boards = { 1 => board }`, `chart.file_system = MockFileSystem.new`, load ERB with `when_loading(file: ..., json: :not_mocked)`
- `current_board` (inherited from ChartBase) returns the board from `@all_boards[@board_id]`
- `random_color` generates a random hex color string

---

## Task 1: CfdDataBuilder — skeleton + daily counts

**Files:**
- Create: `lib/jirametrics/cfd_data_builder.rb`
- Create: `spec/cfd_data_builder_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/cfd_data_builder_spec.rb
# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cfd_data_builder'

describe CfdDataBuilder do
  let(:board) { sample_board }
  let(:date_range) { Date.parse('2021-07-01')..Date.parse('2021-07-10') }

  def build(**overrides)
    defaults = { board: board, issues: [], date_range: date_range }
    CfdDataBuilder.new(**defaults.merge(overrides)).run
  end

  context 'columns' do
    it 'returns visible column names in left-to-right order' do
      expect(build[:columns]).to eq ['Ready', 'In Progress', 'Review', 'Done']
    end
  end

  context 'daily_counts' do
    it 'returns zero counts when no issues are on the board' do
      expect(build[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0, 0, 0]
    end

    it 'counts cumulative totals per column across all dates' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Ready', value_id: 10001, time: '2021-07-02T10:00:00')

      issue2 = empty_issue(created: '2021-07-01', key: 'SP-2')
      add_mock_change(issue: issue2, field: 'status', value: 'In Progress', value_id: 3, time: '2021-07-03T10:00:00')

      result = build(issues: [issue1, issue2])

      # July 1: no issues have reached any column yet
      expect(result[:daily_counts][Date.parse('2021-07-01')]).to eq [0, 0, 0, 0]
      # July 2: issue1 reached Ready (col 0); cumulative: col0+=1
      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [1, 0, 0, 0]
      # July 3: issue2 reached In Progress (col 1); cumulative: col0+=2, col1+=1
      expect(result[:daily_counts][Date.parse('2021-07-03')]).to eq [2, 1, 0, 0]
      # July 10: same as July 3 (no more changes)
      expect(result[:daily_counts][Date.parse('2021-07-10')]).to eq [2, 1, 0, 0]
    end

    it 'returns exactly one key per day in date_range' do
      result = build(date_range: Date.parse('2021-07-05')..Date.parse('2021-07-05'))
      expect(result[:daily_counts].keys).to eq [Date.parse('2021-07-05')]
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
rspec spec/cfd_data_builder_spec.rb
```
Expected: `NameError: uninitialized constant CfdDataBuilder` (or similar load error)

- [ ] **Step 3: Implement `CfdDataBuilder`**

```ruby
# lib/jirametrics/cfd_data_builder.rb
# frozen_string_literal: true

class CfdDataBuilder
  def initialize board:, issues:, date_range:
    @board = board
    @issues = issues
    @date_range = date_range
  end

  def run
    column_map = build_column_map
    issue_states = @issues.map { |issue| process_issue(issue, column_map) }

    {
      columns: @board.visible_columns.map(&:name),
      daily_counts: build_daily_counts(issue_states),
      correction_windows: issue_states.flat_map { |s| s[:correction_windows] }
    }
  end

  private

  def build_column_map
    map = {}
    @board.visible_columns.each_with_index do |column, index|
      column.status_ids.each { |id| map[id] = index }
    end
    map
  end

  # Returns { hwm_timeline: [[date, hwm_value], ...], correction_windows: [...] }
  def process_issue issue, column_map
    high_water_mark = nil
    correction_open_since = nil
    correction_windows = []
    hwm_timeline = []  # sorted chronologically by date

    issue.status_changes.each do |change|
      col_index = column_map[change.value_id]
      next if col_index.nil?

      if high_water_mark.nil? || col_index > high_water_mark
        if correction_open_since
          correction_windows << {
            start_date: correction_open_since,
            end_date: change.time.to_date,
            column_index: high_water_mark
          }
          correction_open_since = nil
        end
        high_water_mark = col_index
        hwm_timeline << [change.time.to_date, high_water_mark]
      elsif col_index < high_water_mark
        correction_open_since ||= change.time.to_date
      end
    end

    if correction_open_since
      correction_windows << {
        start_date: correction_open_since,
        end_date: @date_range.end,
        column_index: high_water_mark
      }
    end

    { hwm_timeline: hwm_timeline, correction_windows: correction_windows }
  end

  def hwm_at hwm_timeline, date
    result = nil
    hwm_timeline.each do |timeline_date, hwm|
      break if timeline_date > date
      result = hwm
    end
    result
  end

  def build_daily_counts issue_states
    column_count = @board.visible_columns.size
    @date_range.each_with_object({}) do |date, result|
      counts = Array.new(column_count, 0)
      issue_states.each do |state|
        hwm = hwm_at(state[:hwm_timeline], date)
        next if hwm.nil?
        (0..hwm).each { |i| counts[i] += 1 }
      end
      result[date] = counts
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
rspec spec/cfd_data_builder_spec.rb
```
Expected: all examples pass

- [ ] **Step 5: Run full test suite**

```bash
rake spec
```
Expected: no regressions

- [ ] **Step 6: Commit**

```bash
git add lib/jirametrics/cfd_data_builder.rb spec/cfd_data_builder_spec.rb
git commit -m "Add CfdDataBuilder skeleton with daily_counts computation"
```

---

## Task 2: CfdDataBuilder — correction windows and edge cases

**Files:**
- Modify: `spec/cfd_data_builder_spec.rb` (add test contexts)
- No changes to implementation needed (already handles these)

- [ ] **Step 1: Add tests for correction windows and edge cases**

Add these contexts to `spec/cfd_data_builder_spec.rb` after the `daily_counts` context:

```ruby
  context 'correction_windows' do
    it 'records a window when an issue moves backwards and recovers' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Reaches Review (col 2), drops to In Progress (col 1), recovers to Review (col 2)
      add_mock_change(issue: issue1, field: 'status', value: 'Review',      value_id: 10011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3,     time: '2021-07-04T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',      value_id: 10011, time: '2021-07-06T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].size).to eq 1
      window = result[:correction_windows].first
      expect(window[:start_date]).to eq Date.parse('2021-07-04')
      expect(window[:end_date]).to eq Date.parse('2021-07-06')
      expect(window[:column_index]).to eq 2  # Review is column index 2
    end

    it 'sets end_date to date_range.end when issue never recovers' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',      value_id: 10011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3,     time: '2021-07-04T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].first[:end_date]).to eq date_range.end
    end

    it 'records one correction window for multiple consecutive backwards moves' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Review',      value_id: 10011, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3,     time: '2021-07-04T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Ready',       value_id: 10001, time: '2021-07-05T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows].size).to eq 1
      expect(result[:correction_windows].first[:start_date]).to eq Date.parse('2021-07-04')
    end

    it 'returns empty correction_windows when there are no backwards moves' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'Ready', value_id: 10001, time: '2021-07-02T10:00:00')
      add_mock_change(issue: issue1, field: 'status', value: 'Done',  value_id: 10002, time: '2021-07-05T10:00:00')

      result = build(issues: [issue1])

      expect(result[:correction_windows]).to be_empty
    end
  end

  context 'edge cases' do
    it 'skips status changes not mapped to any board column' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Status ID 10000 is Backlog — not in visible_columns for this kanban board
      add_mock_change(issue: issue1, field: 'status', value: 'Backlog', value_id: 10000, time: '2021-07-02T10:00:00')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [0, 0, 0, 0]
    end

    it 'counts issues with changes before date_range in the initial snapshot' do
      issue1 = empty_issue(created: '2021-06-01', key: 'SP-1')
      add_mock_change(issue: issue1, field: 'status', value: 'In Progress', value_id: 3, time: '2021-06-15T10:00:00')

      result = build(issues: [issue1])

      # issue1 already in In Progress (col 1) before the range starts — counts col 0 and col 1
      expect(result[:daily_counts][Date.parse('2021-07-01')]).to eq [1, 1, 0, 0]
    end

    it 'contributes 0 to all columns for an issue with no status changes' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0, 0, 0]
    end

    it 'counts all columns when an issue skips directly to the rightmost column' do
      issue1 = empty_issue(created: '2021-07-01', key: 'SP-1')
      # Jumps straight to Done (col 3), skipping Ready, In Progress, Review
      add_mock_change(issue: issue1, field: 'status', value: 'Done', value_id: 10002, time: '2021-07-02T10:00:00')

      result = build(issues: [issue1])

      expect(result[:daily_counts][Date.parse('2021-07-02')]).to eq [1, 1, 1, 1]
    end
  end
```

- [ ] **Step 2: Run spec to verify all tests pass**

```bash
rspec spec/cfd_data_builder_spec.rb
```
Expected: all examples pass (the implementation already handles these cases)

- [ ] **Step 3: If any test fails**, debug and fix `lib/jirametrics/cfd_data_builder.rb`. Then re-run.

- [ ] **Step 4: Run full test suite**

```bash
rake spec
```
Expected: no regressions

- [ ] **Step 5: Commit**

```bash
git add spec/cfd_data_builder_spec.rb
git commit -m "Add CfdDataBuilder correction window and edge case specs"
```

---

## Task 3: CumulativeFlowDiagram chart class + ERB template

**Files:**
- Create: `lib/jirametrics/cumulative_flow_diagram.rb`
- Create: `lib/jirametrics/html/cumulative_flow_diagram.erb`
- Create: `spec/cumulative_flow_diagram_spec.rb`

### Step 1: Write the failing spec

- [ ] **Step 1: Create the chart spec**

```ruby
# spec/cumulative_flow_diagram_spec.rb
# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cumulative_flow_diagram'

describe CumulativeFlowDiagram do
  let(:board) { load_complete_sample_board }
  let(:issues) { load_complete_sample_issues board: board }

  let(:chart) do
    chart = described_class.new(empty_config_block)
    chart.file_system = MockFileSystem.new
    chart.file_system.when_loading(
      file: File.expand_path('./lib/jirametrics/html/cumulative_flow_diagram.erb'),
      json: :not_mocked
    )
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    chart.issues = issues
    chart.date_range = Date.parse('2021-06-01')..Date.parse('2021-09-01')
    chart
  end

  context 'run' do
    it 'renders without error' do
      expect { chart.run }.not_to raise_error
    end

    it 'includes the board column names' do
      output = chart.run
      # complete_sample board visible columns: Ready, In Progress, Review, Done
      expect(output).to include('Ready')
      expect(output).to include('In Progress')
      expect(output).to include('Done')
    end

    it 'includes the segment callback for dashed lines during correction windows' do
      output = chart.run
      expect(output).to include('borderDash')
    end

    it 'sets x-axis max to one day past date_range.end' do
      output = chart.run
      expect(output).to include('2021-09-02')
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
rspec spec/cumulative_flow_diagram_spec.rb
```
Expected: `NameError: uninitialized constant CumulativeFlowDiagram`

### Step 3: Implement the chart class

- [ ] **Step 3: Create `lib/jirametrics/cumulative_flow_diagram.rb`**

```ruby
# lib/jirametrics/cumulative_flow_diagram.rb
# frozen_string_literal: true

require 'jirametrics/cfd_data_builder'

# Used to embed a Chart.js segment callback (which contains JS functions) into
# a JSON-like dataset object. The custom to_json emits raw JS rather than a
# quoted string, following the same pattern as ExpeditedChart::EXPEDITED_SEGMENT.
class CfdSegment
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

class CumulativeFlowDiagram < ChartBase
  def initialize block
    super()
    header_text 'Cumulative Flow Diagram'
    instance_eval(&block)
  end

  def run
    cfd = CfdDataBuilder.new(
      board: current_board,
      issues: issues,
      date_range: date_range
    ).run

    columns          = cfd[:columns]
    daily_counts     = cfd[:daily_counts]
    correction_windows = cfd[:correction_windows]
    column_count     = columns.size

    # Convert cumulative totals to marginal band heights for Chart.js stacking.
    # cumulative[i] = issues that reached column i or further.
    # marginal[i]   = cumulative[i] - cumulative[i+1]  (last column: marginal = cumulative)
    daily_marginals = daily_counts.transform_values do |cumulative|
      cumulative.each_with_index.map do |count, i|
        i < column_count - 1 ? count - cumulative[i + 1] : count
      end
    end

    colors = columns.map { random_color }

    # Datasets in reversed order: done column first (bottom of stack), leftmost last (top).
    data_sets = columns.each_with_index.map do |name, col_index|
      col_windows = correction_windows
        .select { |w| w[:column_index] == col_index }
        .map { |w| { start_date: w[:start_date].to_s, end_date: w[:end_date].to_s } }

      {
        label: name,
        data: date_range.map { |date| { x: date.to_s, y: daily_marginals[date][col_index] } },
        backgroundColor: colors[col_index],
        borderColor: colors[col_index],
        fill: true,
        tension: 0,
        segment: CfdSegment.new(col_windows)
      }
    end.reverse

    # Correction windows for the afterDraw hatch plugin, with dataset index in
    # Chart.js dataset array (reversed: done column = index 0).
    hatch_windows = correction_windows.map do |w|
      {
        dataset_index: column_count - 1 - w[:column_index],
        start_date: w[:start_date].to_s,
        end_date: w[:end_date].to_s,
        color: colors[w[:column_index]]
      }
    end

    wrap_and_render(binding, __FILE__)
  end
end
```

### Step 4: Create the ERB template

- [ ] **Step 4: Create `lib/jirametrics/html/cumulative_flow_diagram.erb`**

```erb
<%= seam_start %>
<div class="chart">
  <canvas id="<%= chart_id %>" width="<%= canvas_width %>" height="<%= canvas_height %>"></canvas>
</div>
<script>
(function() {
  const hatchWindows = <%= hatch_windows.to_json %>;

  // Custom plugin: draws diagonal hatching over correction windows in the affected band.
  // Uses createDiagonalPattern() defined in index.js.
  const cfdHatchPlugin = {
    id: 'cfdHatch',
    afterDraw: function(chart) {
      const ctx = chart.ctx;
      hatchWindows.forEach(function(win) {
        const meta = chart.getDatasetMeta(win.dataset_index);
        if (!meta || !meta.data.length) return;

        const startX = chart.scales.x.getPixelForValue(new Date(win.start_date).getTime());
        const endX   = chart.scales.x.getPixelForValue(new Date(win.end_date).getTime());

        // Draw a vertical hatched slice at each data point within the correction window.
        meta.data.forEach(function(point, i) {
          if (point.x < startX || point.x > endX) return;
          const sliceLeft  = i > 0 ? meta.data[i - 1].x : startX;
          const top        = point.y;
          const bottom     = point.base;
          if (top === undefined || bottom === undefined || top >= bottom) return;
          ctx.save();
          ctx.fillStyle = createDiagonalPattern(win.color);
          ctx.fillRect(sliceLeft, top, point.x - sliceLeft, bottom - top);
          ctx.restore();
        });
      });
    }
  };

  new Chart(document.getElementById('<%= chart_id %>').getContext('2d'), {
    type: 'line',
    plugins: [cfdHatchPlugin],
    data: {
      datasets: <%= JSON.generate(data_sets) %>
    },
    options: {
      responsive: <%= canvas_responsive? %>,
      scales: {
        x: {
          type: 'time',
          time: { format: 'YYYY-MM-DD' },
          min: "<%= date_range.begin.to_s %>",
          max: "<%= (date_range.end + 1).to_s %>",
          grid: { color: <%= CssVariable['--grid-line-color'].to_json %> }
        },
        y: {
          stacked: true,
          min: 0,
          title: { display: true, text: 'Number of items' },
          grid: { color: <%= CssVariable['--grid-line-color'].to_json %> }
        }
      },
      plugins: {
        legend: {
          reverse: true
        }
      }
    }
  });
})();
</script>
<%= seam_end %>
```

- [ ] **Step 5: Run the chart spec**

```bash
rspec spec/cumulative_flow_diagram_spec.rb
```
Expected: all examples pass

- [ ] **Step 6: Run full test suite**

```bash
rake spec
```
Expected: no regressions

- [ ] **Step 7: Run RuboCop on new files**

```bash
rubocop lib/jirametrics/cfd_data_builder.rb lib/jirametrics/cumulative_flow_diagram.rb
```
Fix any offenses found before committing.

- [ ] **Step 8: Commit**

```bash
git add lib/jirametrics/cfd_data_builder.rb \
        lib/jirametrics/cumulative_flow_diagram.rb \
        lib/jirametrics/html/cumulative_flow_diagram.erb \
        spec/cumulative_flow_diagram_spec.rb
git commit -m "Add CumulativeFlowDiagram chart with backwards-movement visualization"
```

---

## Notes for Implementer

**`CfdSegment#to_json` pattern:** The custom `to_json` emits raw JavaScript (not a quoted string), so `JSON.generate(data_sets)` produces JS-compatible output with embedded functions — not valid JSON, but valid JS that Chart.js consumes. This is the same pattern used in `ExpeditedChart::EXPEDITED_SEGMENT`. Do not add quotes around the segment value.

**Stacking and legend order:** `y.stacked: true` tells Chart.js to stack datasets. Datasets are passed in reverse order (Done first) so the leftmost column ends up on top visually. `legend.reverse: true` restores left-to-right legend display.

**`date_range.end + 1` on x-axis max:** Chart.js interprets `max` as the start of that day, which would cut off the last day. Adding 1 day corrects this (documented in CLAUDE.md).

**Hatching implementation:** `createDiagonalPattern(color)` is defined in `lib/jirametrics/html/index.js` and is available globally in the browser context. The `afterDraw` plugin draws over each data point's slice within the correction window x-range using the pattern as `fillStyle`.

**RuboCop:** After any Ruby file changes, run `rubocop` on those files and fix offenses. Ignore pre-existing warnings about `plugins:` vs `require:` in `.rubocop.yml`.
