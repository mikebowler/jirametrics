# CFD Column Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `column_rules` DSL to `CumulativeFlowDiagram` allowing users to override band colours and ignore specific columns, and extend `CfdDataBuilder` to accept an explicit column list so ignored columns are excluded from calculations.

**Architecture:** A new `CfdColumnRules` private inner class (subclass of `Rules`) carries `color` and `ignore`. `CumulativeFlowDiagram#column_rules` stores a block that is called once per `BoardColumn` during `run`; ignored columns are filtered out before a `columns:` array is passed to `CfdDataBuilder`. `CfdDataBuilder` gains an optional `columns:` keyword defaulting to `board.visible_columns`.

**Tech Stack:** Ruby, RSpec, existing `Rules` base class (`lib/jirametrics/rules.rb`).

---

### Task 1: Add `columns:` keyword to `CfdDataBuilder`

**Files:**
- Modify: `lib/jirametrics/cfd_data_builder.rb`
- Test: `spec/cfd_data_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

Add inside the `describe CfdDataBuilder` block in `spec/cfd_data_builder_spec.rb`:

```ruby
context 'columns: override' do
  it 'uses the provided columns instead of board.visible_columns' do
    # Pass only the first two columns (Ready, In Progress); Done and Review are excluded
    two_columns = board.visible_columns.first(2)
    result = build(columns: two_columns)
    expect(result[:columns]).to eq ['Ready', 'In Progress']
  end

  it 'does not track issues that reach an excluded column' do
    two_columns = board.visible_columns.first(2) # Ready (10001), In Progress (3)
    issue = empty_issue(created: '2021-07-01', key: 'SP-1')
    # Issue goes straight to Review (10011), which is not in the two-column set
    add_mock_change(issue: issue, field: 'status', value: 'Review',
      value_id: 10_011, time: '2021-07-02T10:00:00')
    result = build(columns: two_columns, issues: [issue])
    # Issue's status_id 10011 not in column_map → high-water-mark stays nil → not counted
    expect(result[:daily_counts][Date.parse('2021-07-05')]).to eq [0, 0]
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
rake spec
```

Expected: 2 failures mentioning unknown keyword `columns:`.

- [ ] **Step 3: Update `CfdDataBuilder#initialize` to accept `columns:`**

In `lib/jirametrics/cfd_data_builder.rb`, change `initialize` and replace all uses of `@board.visible_columns` with `@columns`:

```ruby
def initialize board:, issues:, date_range:, columns: nil
  @board = board
  @issues = issues
  @date_range = date_range
  @columns = columns || board.visible_columns
end
```

Then in `build_column_map`, `run`, and `build_daily_counts`, replace every occurrence of `@board.visible_columns` with `@columns`. The three locations are:

- `build_column_map`: `@board.visible_columns.each_with_index` → `@columns.each_with_index`
- `run`: `columns: @board.visible_columns.map(&:name)` → `columns: @columns.map(&:name)`
- `build_daily_counts`: `column_count = @board.visible_columns.size` → `column_count = @columns.size`

- [ ] **Step 4: Run the tests and verify they pass**

```bash
rake spec
```

Expected: all tests pass.

---

### Task 2: Add `CfdColumnRules` and `column_rules` to `CumulativeFlowDiagram`

**Files:**
- Modify: `lib/jirametrics/cumulative_flow_diagram.rb`
- Test: `spec/cumulative_flow_diagram_spec.rb`

#### Background

`Rules` (`lib/jirametrics/rules.rb`) already provides `ignore` / `ignored?`. We subclass it with a simple `color` attribute. The chart's `run` method currently builds `border_colors` and `fill_colors` from `columns.map { random_color }`. We replace that with per-column rule lookup.

`hex_to_rgba` (already on the chart) converts `#rrggbb` → `rgba(r,g,b,alpha)`. If the user supplies a non-hex color string, we use it as-is for both border and fill (limitation documented separately).

`empty_config_block` in `spec_helper.rb` returns `->(_) {}` — a lambda that accepts the chart object (passed as block-arg by `instance_eval`) and ignores it. For tests that need a custom DSL block, pass a `proc { ... }` instead (no argument needed; `instance_eval` sets `self` to the chart so methods like `column_rules` resolve directly).

- [ ] **Step 1: Write the failing tests**

Add inside the `context 'run'` block in `spec/cumulative_flow_diagram_spec.rb`:

```ruby
context 'column_rules' do
  def chart_with_rules(&block)
    c = described_class.new(block)
    c.file_system = MockFileSystem.new
    c.file_system.when_loading(
      file: File.expand_path('./lib/jirametrics/html/cumulative_flow_diagram.erb'),
      json: :not_mocked
    )
    c.board_id = 1
    c.all_boards = { 1 => board }
    c.issues = issues
    c.date_range = Date.parse('2021-06-01')..Date.parse('2021-09-01')
    c
  end

  it 'uses a custom colour for the named column' do
    output = chart_with_rules {
      column_rules do |column, rule|
        rule.color = '#abcdef' if column.name == 'In Progress'
      end
    }.run
    expect(output).to include('#abcdef')
  end

  it 'excludes an ignored column from the output' do
    output = chart_with_rules {
      column_rules do |column, rule|
        rule.ignore if column.name == 'Done'
      end
    }.run
    # 'Done' must not appear as a dataset label
    expect(output).not_to include('"Done"')
  end

  it 'still includes non-ignored columns when one is ignored' do
    output = chart_with_rules {
      column_rules do |column, rule|
        rule.ignore if column.name == 'Done'
      end
    }.run
    expect(output).to include('In Progress')
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
rake spec
```

Expected: 3 failures — `column_rules` method not defined.

- [ ] **Step 3: Add `CfdColumnRules` inner class and `column_rules` method**

In `lib/jirametrics/cumulative_flow_diagram.rb`, add immediately after the `Segment` inner class (before `private_constant :Segment`):

```ruby
class CfdColumnRules < Rules
  attr_accessor :color
end
private_constant :CfdColumnRules
```

Add a `column_rules` DSL method in the public interface (before `def run`):

```ruby
def column_rules &block
  @column_rules_block = block
end
```

- [ ] **Step 4: Update `run` to apply column rules**

Replace the `run` method body with the following. The logic:
1. Build per-column rules by calling the block (if any) for each `BoardColumn`.
2. Zip columns with rules, filter out ignored ones.
3. Pass the remaining columns to `CfdDataBuilder` via `columns:`.
4. Derive colors: hex custom color → derive rgba fill; non-hex custom color → use as-is for fill; no custom color → `random_color` + derived rgba.

```ruby
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

  fill_colors = active_rules.zip(border_colors).map do |rules, border|
    if rules.color.nil? || rules.color.match?(/\A#[0-9a-fA-F]{6}\z/)
      hex_to_rgba(border, 0.35)
    else
      rules.color
    end
  end

  # Datasets in reversed order: rightmost column first (bottom of stack), leftmost last (top).
  data_sets = columns.each_with_index.map do |name, col_index|
    col_windows = correction_windows
      .select { |w| w[:column_index] == col_index }
      .map { |w| { start_date: w[:start_date].to_s, end_date: w[:end_date].to_s } }

    {
      label: name,
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
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
rake spec
```

Expected: all tests pass, including the 3 new column_rules tests.

- [ ] **Step 6: Run RuboCop on modified files**

```bash
rubocop lib/jirametrics/cfd_data_builder.rb lib/jirametrics/cumulative_flow_diagram.rb spec/cfd_data_builder_spec.rb spec/cumulative_flow_diagram_spec.rb
```

Fix any offenses reported (ignore pre-existing `plugins:` warning in `.rubocop.yml`).
