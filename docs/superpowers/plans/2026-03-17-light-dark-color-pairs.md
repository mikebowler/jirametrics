# Light/Dark Mode Color Pairs Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow grouping rules to accept `[light_color, dark_color]` pairs so charts look correct in both light and dark mode.

**Architecture:** `GroupingRules#color=` detects an array, generates a deterministic CSS variable name from the pair's SHA256 hash, and stores the pair. Charts accumulate pairs in `generated_colors` during `run`. `HtmlReportConfig` collects pairs from each chart via `execute_chart` and emits a `<style>` block appended to the CSS (inside `<head>`) when building the HTML report.

**Tech Stack:** Ruby, RSpec. `Digest::SHA256` from Ruby stdlib (no new gems).

**Spec:** `docs/superpowers/specs/2026-03-17-light-dark-color-pairs-design.md`

---

## File Map

| File | Change |
|------|--------|
| `lib/jirametrics/grouping_rules.rb` | Extend `color=` to handle arrays; add `color_pair` reader |
| `lib/jirametrics/chart_base.rb` | Add `generated_colors` accessor; initialise in `initialize` |
| `lib/jirametrics/groupable_issue_chart.rb` | Merge `color_pair` into `@generated_colors` in `group_issues` |
| `lib/jirametrics/daily_wip_chart.rb` | Merge `color_pair` into `@generated_colors` in `configure_rule` |
| `lib/jirametrics/html_report_config.rb` | Add `@generated_colors` to `initialize`; reset+merge in `execute_chart`; override `load_css` |
| `spec/grouping_rules_spec.rb` | New file |
| `spec/chart_base_spec.rb` | Add `generated_colors` tests |
| `spec/groupable_issue_chart_spec.rb` | Add color pair propagation test |
| `spec/daily_wip_chart_spec.rb` | Add color pair propagation test |
| `spec/html_report_config_spec.rb` | Add accumulation + CSS emission tests |

---

### Task 1: `GroupingRules` — color pair support

**Files:**
- Modify: `lib/jirametrics/grouping_rules.rb`
- Create: `spec/grouping_rules_spec.rb`

Run all tests between steps with: `rake spec`

- [ ] **Step 1: Create `spec/grouping_rules_spec.rb` with failing tests**

```ruby
# frozen_string_literal: true

require './spec/spec_helper'

describe GroupingRules do
  subject(:rules) { described_class.new }

  context 'color= with a single color' do
    it 'accepts a hex string' do
      rules.color = '#4bc14b'
      expect(rules.color).to eq '#4bc14b'
    end

    it 'accepts a css variable string' do
      rules.color = '--type-story-color'
      expect(rules.color).to eq CssVariable['--type-story-color']
    end

    it 'leaves color_pair nil' do
      rules.color = '#4bc14b'
      expect(rules.color_pair).to be_nil
    end

    it 'clears color_pair when reassigned from an array to a single color' do
      rules.color = ['#4bc14b', '#2a7a2a']
      rules.color = '#ff0000'
      expect(rules.color_pair).to be_nil
    end
  end

  context 'color= with a [light, dark] array' do
    it 'sets color to a CssVariable with a deterministic generated name' do
      rules.color = ['#4bc14b', '#2a7a2a']
      expect(rules.color).to be_a CssVariable
      expect(rules.color.name).to match(/^--generated-color-[0-9a-f]{8}$/)
    end

    it 'always produces the same variable name for the same pair' do
      rules.color = ['#4bc14b', '#2a7a2a']
      name1 = rules.color.name

      other = described_class.new
      other.color = ['#4bc14b', '#2a7a2a']
      expect(other.color.name).to eq name1
    end

    it 'produces different variable names for different pairs' do
      rules.color = ['#4bc14b', '#2a7a2a']
      other = described_class.new
      other.color = ['#ff0000', '#880000']
      expect(rules.color.name).not_to eq other.color.name
    end

    it 'stores the pair in color_pair' do
      rules.color = ['#4bc14b', '#2a7a2a']
      expect(rules.color_pair).to eq({ light: '#4bc14b', dark: '#2a7a2a' })
    end

    it 'two rules with the same pair are eql?' do
      rules.label = 'Story'
      rules.color = ['#4bc14b', '#2a7a2a']
      other = described_class.new
      other.label = 'Story'
      other.color = ['#4bc14b', '#2a7a2a']
      expect(rules).to eql(other)
    end

    it 'raises ArgumentError when array does not have exactly two elements' do
      expect { rules.color = ['#4bc14b'] }.to raise_error(
        ArgumentError, 'Color pair must have exactly two elements: [light_color, dark_color]'
      )
    end

    it 'raises ArgumentError when array contains a non-string element' do
      expect { rules.color = ['#4bc14b', 123] }.to raise_error(
        ArgumentError, 'Color pair elements must be strings'
      )
    end

    it 'raises ArgumentError when array contains a css variable reference' do
      expect { rules.color = ['#4bc14b', '--some-var'] }.to raise_error(
        ArgumentError,
        'CSS variable references are not supported as color pair elements; use a literal color value instead'
      )
    end
  end
end
```

- [ ] **Step 2: Run tests and confirm they fail**

```
rake spec
```

Expected: several failures in `grouping_rules_spec.rb` — `undefined method 'color_pair'` and similar.

- [ ] **Step 3: Implement the changes in `lib/jirametrics/grouping_rules.rb`**

```ruby
# frozen_string_literal: true

require 'digest'

class GroupingRules < Rules
  attr_accessor :label, :issue_hint
  attr_reader :color, :color_pair

  def eql? other
    other.label == @label && other.color == @color
  end

  def group
    [@label, @color]
  end

  def color= color
    if color.is_a?(Array)
      raise ArgumentError, 'Color pair must have exactly two elements: [light_color, dark_color]' unless color.size == 2
      raise ArgumentError, 'Color pair elements must be strings' unless color.all? { |c| c.is_a?(String) }

      if color.any? { |c| c.start_with?('--') }
        raise ArgumentError,
          'CSS variable references are not supported as color pair elements; use a literal color value instead'
      end

      light, dark = color
      short_hash = Digest::SHA256.hexdigest("#{light}|#{dark}")[0, 8]
      @color_pair = { light: light, dark: dark }
      @color = CssVariable["--generated-color-#{short_hash}"]
    else
      color = CssVariable[color] unless color.is_a?(CssVariable)
      @color = color
      @color_pair = nil
    end
  end
end
```

- [ ] **Step 4: Run tests and confirm they pass**

```
rake spec
```

Expected: all tests pass, including the new `grouping_rules_spec.rb` tests.

---

### Task 2: `ChartBase` — `generated_colors` accessor

**Files:**
- Modify: `lib/jirametrics/chart_base.rb`
- Modify: `spec/chart_base_spec.rb`

- [ ] **Step 1: Add failing test to `spec/chart_base_spec.rb`**

Add inside the existing `describe ChartBase do` block:

```ruby
context 'generated_colors' do
  it 'returns an empty hash by default' do
    expect(described_class.new.generated_colors).to eq({})
  end
end
```

- [ ] **Step 2: Run tests and confirm the new test fails**

```
rake spec
```

Expected: `NoMethodError: undefined method 'generated_colors'`

- [ ] **Step 3: Add `generated_colors` to `ChartBase`**

In `lib/jirametrics/chart_base.rb`, add `generated_colors` to the `attr_accessor` line at the top:

```ruby
attr_accessor :timezone_offset, :board_id, :all_boards, :date_range,
  :time_range, :data_quality, :holiday_dates, :settings, :issues, :file_system,
  :atlassian_document_format, :x_axis_title, :y_axis_title, :fix_versions,
  :generated_colors
```

And initialise it in `initialize`:

```ruby
def initialize
  @chart_colors = {
    'Story'  => CssVariable['--type-story-color'],
    'Task'   => CssVariable['--type-task-color'],
    'Bug'    => CssVariable['--type-bug-color'],
    'Defect' => CssVariable['--type-bug-color'],
    'Spike'  => CssVariable['--type-spike-color']
  }
  @canvas_width = 800
  @canvas_height = 200
  @canvas_responsive = true
  @generated_colors = {}
end
```

- [ ] **Step 4: Run tests and confirm they pass**

```
rake spec
```

Expected: all tests pass.

---

### Task 3: `GroupableIssueChart` — populate `generated_colors`

**Files:**
- Modify: `lib/jirametrics/groupable_issue_chart.rb`
- Modify: `spec/groupable_issue_chart_spec.rb`

- [ ] **Step 1: Add failing test to `spec/groupable_issue_chart_spec.rb`**

The spec already uses `ThroughputChart` as a concrete subject. Add:

```ruby
it 'populates generated_colors when a color pair is used' do
  subject = ThroughputChart.new ->(_) {}
  subject.grouping_rules do |_object, rules|
    rules.label = 'Group A'
    rules.color = ['#4bc14b', '#2a7a2a']
  end
  subject.group_issues([1])
  expect(subject.generated_colors).not_to be_empty
  expect(subject.generated_colors.values.first).to eq({ light: '#4bc14b', dark: '#2a7a2a' })
end

it 'does not populate generated_colors for single colors' do
  subject = ThroughputChart.new ->(_) {}
  subject.grouping_rules do |_object, rules|
    rules.label = 'Group A'
    rules.color = '#4bc14b'
  end
  subject.group_issues([1])
  expect(subject.generated_colors).to be_empty
end
```

- [ ] **Step 2: Run tests and confirm the new tests fail**

```
rake spec
```

Expected: both new tests fail — `generated_colors` remains empty.

- [ ] **Step 3: Update `group_issues` in `lib/jirametrics/groupable_issue_chart.rb`**

After the call to `@group_by_block.call(issue, rules)`, add the merge:

```ruby
def group_issues completed_issues
  result = {}
  ignored_issues = []
  @issue_hints = {}
  completed_issues.each do |issue|
    rules = GroupingRules.new
    @group_by_block.call(issue, rules)
    @generated_colors[rules.color.name] = rules.color_pair if rules.color_pair
    if rules.ignored?
      ignored_issues << issue
      next
    end

    @issue_hints[issue] = rules.issue_hint
    (result[rules] ||= []) << issue
  end

  completed_issues.reject! { |issue| ignored_issues.include? issue }

  result.each_key do |rules|
    rules.color = random_color if rules.color.nil?
  end
  result
end
```

Note: `rules.color.name` works here because when `color_pair` is set, `rules.color` is always a `CssVariable` (never a plain string).

- [ ] **Step 4: Run tests and confirm they pass**

```
rake spec
```

Expected: all tests pass.

---

### Task 4: `DailyWipChart` — populate `generated_colors`

**Files:**
- Modify: `lib/jirametrics/daily_wip_chart.rb`
- Modify: `spec/daily_wip_chart_spec.rb`

- [ ] **Step 1: Add failing test to `spec/daily_wip_chart_spec.rb`**

Add a new `context` block inside `describe DailyWipChart do`:

```ruby
context 'generated_colors' do
  it 'populates generated_colors when a color pair is used in grouping_rules' do
    chart.issues = [issue1]
    chart.grouping_rules do |_issue, rules|
      rules.label = 'Group A'
      rules.color = ['#4bc14b', '#2a7a2a']
    end
    chart.configure_rule issue: issue1, date: Date.parse('2022-01-15')
    expect(chart.generated_colors).not_to be_empty
    expect(chart.generated_colors.values.first).to eq({ light: '#4bc14b', dark: '#2a7a2a' })
  end

  it 'does not populate generated_colors for single colors' do
    chart.issues = [issue1]
    chart.grouping_rules do |_issue, rules|
      rules.label = 'Group A'
      rules.color = '#4bc14b'
    end
    chart.configure_rule issue: issue1, date: Date.parse('2022-01-15')
    expect(chart.generated_colors).to be_empty
  end
end
```

- [ ] **Step 2: Run tests and confirm the new tests fail**

```
rake spec
```

Expected: both new tests fail — `generated_colors` remains empty.

- [ ] **Step 3: Update `configure_rule` in `lib/jirametrics/daily_wip_chart.rb`**

After the call to `@group_by_block.call issue, rules`, add:

```ruby
def configure_rule issue:, date:
  raise "#{self.class}: grouping_rules must be set" if @group_by_block.nil?

  rules = DailyGroupingRules.new
  rules.current_date = date
  @group_by_block.call issue, rules
  @generated_colors[rules.color.name] = rules.color_pair if rules.color_pair
  rules
end
```

- [ ] **Step 4: Run tests and confirm they pass**

```
rake spec
```

Expected: all tests pass.

---

### Task 5: `HtmlReportConfig` — accumulate and emit generated CSS

**Files:**
- Modify: `lib/jirametrics/html_report_config.rb`
- Modify: `spec/html_report_config_spec.rb`

- [ ] **Step 1: Add failing tests to `spec/html_report_config_spec.rb`**

Add a new context block. The `TestableChart` class at the top of the spec already subclasses `ChartBase` with a simple `run` method — extend it to support color pairs:

```ruby
context 'generated_colors accumulation' do
  let(:config) do
    described_class.new(file_config: file_config, block: nil).tap do |c|
      c.board_id 1
    end
  end

  it 'initialises @generated_colors to an empty hash' do
    expect(config.instance_variable_get(:@generated_colors)).to eq({})
  end

  it 'merges generated_colors from a chart after execute_chart' do
    chart = TestableChart.new(nil)
    def chart.run
      @generated_colors['--generated-color-aabbccdd'] = { light: '#4bc14b', dark: '#2a7a2a' }
      'html'
    end
    config.execute_chart chart
    expect(config.instance_variable_get(:@generated_colors)).to eq(
      '--generated-color-aabbccdd' => { light: '#4bc14b', dark: '#2a7a2a' }
    )
  end

  it 'merges idempotently when two charts use the same pair' do
    pair = { light: '#4bc14b', dark: '#2a7a2a' }
    2.times do
      chart = TestableChart.new(nil)
      chart.define_singleton_method(:run) do
        @generated_colors['--generated-color-aabbccdd'] = pair
        'html'
      end
      config.execute_chart chart
    end
    expect(config.instance_variable_get(:@generated_colors).size).to eq 1
  end

  it 'resets chart.generated_colors to {} before each run' do
    chart = TestableChart.new(nil)
    chart.generated_colors = { '--generated-color-old' => { light: 'red', dark: 'darkred' } }
    colors_at_run_start = nil
    chart.define_singleton_method(:run) do
      colors_at_run_start = @generated_colors.dup
      'html'
    end
    config.execute_chart chart
    expect(colors_at_run_start).to eq({})
  end
end

context 'load_css with generated colors' do
  before do
    ['lib/jirametrics/html/index.css', 'Gemfile'].each do |unmocked_file|
      exporter.file_system.when_loading file: unmocked_file, json: :not_mocked
    end
  end

  let(:config) do
    described_class.new(file_config: file_config, block: nil).tap do |c|
      c.board_id 1
    end
  end

  it 'appends nothing when generated_colors is empty' do
    base_css = config.load_css(html_directory: 'lib/jirametrics/html')
    config2 = described_class.new(file_config: file_config, block: nil)
    config2.board_id 1
    config2.instance_variable_set(:@generated_colors, {})
    expect(config2.load_css(html_directory: 'lib/jirametrics/html')).to eq base_css
  end

  it 'appends all three selectors when generated_colors is non-empty' do
    config.instance_variable_set(:@generated_colors, {
      '--generated-color-aabbccdd' => { light: '#4bc14b', dark: '#2a7a2a' }
    })
    css = config.load_css(html_directory: 'lib/jirametrics/html')
    expect(css).to include(':root')
    expect(css).to include('--generated-color-aabbccdd: #4bc14b')
    expect(css).to include('@media (prefers-color-scheme: dark)')
    expect(css).to include('html[data-theme="dark"]')
    expect(css).to include('--generated-color-aabbccdd: #2a7a2a')
  end
end
```

- [ ] **Step 2: Run tests and confirm the new tests fail**

```
rake spec
```

Expected: failures — `load_css` not overridden yet, `@generated_colors` not initialised, etc.

- [ ] **Step 3: Implement the changes in `lib/jirametrics/html_report_config.rb`**

**In `initialize`**, add `@generated_colors = {}`:

```ruby
def initialize file_config:, block:
  @file_config = file_config
  @block = block
  @sections = []         # Where we store the chunks of text that will be assembled into the HTML
  @charts = []           # Where we store all the charts we executed so we can assert against them.
  @generated_colors = {} # Accumulated color pairs from all charts for CSS emission
end
```

**In `execute_chart`**, reset before `chart.before_run` and merge after `html chart.run`:

```ruby
def execute_chart chart, &after_init_block
  project_config = @file_config.project_config

  chart.file_system = file_system
  chart.issues = issues
  chart.time_range = project_config.time_range
  chart.timezone_offset = timezone_offset
  chart.settings = settings
  chart.atlassian_document_format = project_config.atlassian_document_format

  chart.all_boards = project_config.all_boards
  chart.board_id = find_board_id
  chart.holiday_dates = project_config.exporter.holiday_dates
  chart.fix_versions = project_config.fix_versions

  time_range = @file_config.project_config.time_range
  chart.date_range = time_range.begin.to_date..time_range.end.to_date
  chart.aggregated_project = project_config.aggregated_project?

  after_init_block&.call chart

  @charts << chart
  chart.generated_colors = {}
  chart.before_run
  html chart.run
  @generated_colors.merge!(chart.generated_colors)
end
```

**Add `load_css` override and private helper** (add before the final `end`):

```ruby
def load_css html_directory:
  css = super(html_directory: html_directory)
  return css if @generated_colors.empty?

  css + "\n" + generated_css_block
end

private

def generated_css_block
  light_vars = @generated_colors.map { |name, pair| "  #{name}: #{pair[:light]};" }.join("\n")
  dark_vars  = @generated_colors.map { |name, pair| "  #{name}: #{pair[:dark]};"  }.join("\n")

  <<~CSS
    :root {
    #{light_vars}
    }
    @media (prefers-color-scheme: dark) {
      :root {
    #{dark_vars}
      }
    }
    html[data-theme="dark"] {
    #{dark_vars}
    }
  CSS
end
```

- [ ] **Step 4: Run tests and confirm they pass**

```
rake spec
```

Expected: all tests pass, including all new tests.

- [ ] **Step 5: Run rubocop on modified files**

```
rubocop lib/jirametrics/grouping_rules.rb lib/jirametrics/chart_base.rb \
        lib/jirametrics/groupable_issue_chart.rb lib/jirametrics/daily_wip_chart.rb \
        lib/jirametrics/html_report_config.rb
```

Fix any new offenses (ignore pre-existing ones).
