# Scatterplot Configurable Percentiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let scatterplot users configure which percentile lines are drawn, including several or none, instead of a hardcoded 85th.

**Architecture:** A single cascading `percentiles` setter. The chart-level value defines the overall (whole data set) lines and supplies the default for each group; `rule.percentiles` inside `grouping_rules` overrides it for one group. The calculation returns a list of `[percentile, value]` pairs built on the existing `percentile_value`. Each pair becomes one Chart.js line annotation carrying a hover-revealed label.

**Tech Stack:** Ruby, RSpec, ERB, Chart.js with chartjs-plugin-annotation 3.1.0.

**Design doc:** `docs/superpowers/specs/2026-08-10-scatterplot-configurable-percentiles-design.md`

## Global Constraints

- 85 stays the default. A config that does not mention `percentiles` must render byte-for-byte what it renders today, including the legend label `Story (85% at 81 days)`.
- `nil` means inherit, `[]` means explicitly none. Never initialise `percentiles` to `[]`.
- `percentiles` must stay out of `GroupingRules#eql?`, out of `#group`, and out of any future `#hash`.
- Percentile lines are computed from the full data set, never from capped display values. `spec/cycletime_scatterplot_spec.rb:250` guards this; it must keep passing.
- Ruby hash keys are snake_case.
- No em-dashes in comments, prose, or generated output.
- Prefer multiline `unless/end` over trailing `unless` when the statement spans lines.
- Every `rubocop:disable` needs an explanatory comment.
- Use `aggregate_failures do ... end` blocks, not the `:aggregate_failures` tag.
- Quality gate before every commit: `bundle exec rspec` (0 failures) and `bundle exec rubocop` (0 offenses).
- Do not modify Data Centre code.

---

### Task 1: `GroupingRules#percentiles` accessor

The per-group override slot. Nothing consumes it yet; this task only establishes that it exists, defaults to `nil`, and does not disturb group identity.

**Files:**
- Modify: `lib/jirametrics/grouping_rules.rb:4`
- Test: `spec/grouping_rules_spec.rb`

**Interfaces:**
- Produces: `GroupingRules#percentiles` (reader) and `#percentiles=` (writer). Value is `nil` or an Array of Integer.

- [ ] **Step 1: Write the failing test**

Add to `spec/grouping_rules_spec.rb`:

```ruby
describe '#percentiles' do
  it 'defaults to nil so that unset is distinguishable from empty' do
    expect(described_class.new.percentiles).to be_nil
  end

  it 'round trips a list' do
    rules = described_class.new
    rules.percentiles = [50, 85]
    expect(rules.percentiles).to eq [50, 85]
  end

  it 'does not participate in group identity' do
    one = described_class.new.tap { |r| r.label = 'Story'; r.percentiles = [50] }
    two = described_class.new.tap { |r| r.label = 'Story'; r.percentiles = [98] }
    aggregate_failures do
      expect(one).to eql(two)
      expect(one.group).to eq two.group
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/grouping_rules_spec.rb -e '#percentiles'`
Expected: FAIL with `NoMethodError: undefined method 'percentiles='`. If the file `spec/grouping_rules_spec.rb` does not exist, create it with the standard header (`# frozen_string_literal: true`, `require './spec/spec_helper'`, `require 'jirametrics/grouping_rules'`, `describe GroupingRules do`).

- [ ] **Step 3: Write minimal implementation**

In `lib/jirametrics/grouping_rules.rb`, add `percentiles` to the existing `attr_accessor` line:

```ruby
attr_accessor :label, :issue_hint, :label_hint, :percentiles
```

Do not touch `eql?` or `group`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/grouping_rules_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/grouping_rules.rb spec/grouping_rules_spec.rb && \
git commit -m "Add a per-group percentiles slot to GroupingRules

nil means inherit the chart default; it deliberately stays out of group
identity so two groups differing only in percentiles do not split."
```

---

### Task 2: The `percentiles` chart-level setter

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb:11-25`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `TimeBasedScatterplot#percentiles(list = nil)` reader/writer in the config-block idiom. Returns the current Array. Defaults to `[85]`.

The reader/writer-in-one shape matches `TimeBasedHistogram#percentiles` (`time_based_histogram.rb:23-26`), which is the pattern the family is converging on. Note that a bare `percentiles` call must return the value rather than clear it, which is why the argument defaults to `nil` and is only assigned when non-nil.

- [ ] **Step 1: Write the failing test**

Add to `spec/cycletime_scatterplot_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#percentiles'`
Expected: FAIL. The first example fails with `expected: [85], got: nil` rather than a NoMethodError, because `percentiles` does not yet exist as a method but `chart.percentiles` will raise NoMethodError. Confirm you see a genuine assertion failure on at least one example after Step 3 is partially done; a NoMethodError alone is not a validated red.

- [ ] **Step 3: Write minimal implementation**

In `lib/jirametrics/time_based_scatterplot.rb`, set the default in `initialize` and add the setter:

```ruby
def initialize
  super

  @percentage_lines = []
  @highest_y_value = 0
  @percentiles = [85]
end

# Percentile reference lines. The chart level value defines the lines drawn across the whole
# data set AND the default for each group; a group can override with rule.percentiles.
# An empty list switches the lines off.
def percentiles list = nil
  @percentiles = validate_percentiles(list) unless list.nil?
  @percentiles
end

```

and add this to the existing `private` section at the bottom of the file (below the `private`
keyword at `time_based_scatterplot.rb:158`, alongside `cap_label` and `filtered_values`). Do
not write `private def`; RuboCop's `Style/AccessModifierDeclarations` enforces the grouped
style and would fail the gate.

```ruby
def validate_percentiles list
  list.each do |percentile|
    raise ArgumentError, "percentile #{percentile} must be an integer" unless percentile.is_a? Integer

    unless percentile.between?(0, 100)
      raise ArgumentError, "percentile #{percentile} must be between 0 and 100"
    end
  end
  list.uniq.sort
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Add a percentiles setter to the scatterplot family

Defaults to [85] so existing configs are unchanged. Validates eagerly
because a bad percentile silently produces a wrong chart."
```

---

### Task 3: Calculate a list of percentile lines

Replaces the single hardcoded value with a list. `calculate_percent_line` is kept as a thin wrapper because `spec/cycletime_scatterplot_spec.rb:251` calls it directly to guard the cap invariant, and that guard must keep working.

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb:123-125`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `#percentiles` from Task 2, `#percentile_value(items, percentile)` which already exists at `time_based_scatterplot.rb:127`.
- Produces: `#percentile_lines_for(items, percentiles)` returning `Array<Array(Integer, Numeric)>`, sorted by percentile ascending, with entries whose value is `nil` removed.

- [ ] **Step 1: Write the failing test**

```ruby
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
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#percentile_lines_for'`
Expected: FAIL with `NoMethodError: undefined method 'percentile_lines_for'`, then after adding a stub returning `[]`, a genuine assertion failure `expected: [50, 85], got: []`. Reach that assertion failure before implementing.

- [ ] **Step 3: Write minimal implementation**

```ruby
# Returns [[percentile, value], ...] for the requested percentiles, dropping any that have no
# value because the item list is empty after filtering.
def percentile_lines_for items, percentiles
  percentiles.filter_map do |percentile|
    value = percentile_value items, percentile
    [percentile, value] unless value.nil?
  end
end

# Temporary bridge so the cap invariant test and the description keep working while the other
# tasks land. Task 8 deletes this and repoints the test at percentile_value.
def calculate_percent_line items
  percentile_value items, 85
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb`
Expected: PASS, including the existing `statistics are unaffected by capping` example.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Calculate percentile lines as a list rather than a single value"
```

---

### Task 4: Resolve each group's effective percentiles, and raise on conflict

**Files:**
- Modify: `lib/jirametrics/groupable_issue_chart.rb:19-43`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `GroupingRules#percentiles` from Task 1.
- Produces: `group_issues` raises `ArgumentError` when two issues in one group are assigned different non-nil percentile lists. The retained rules object keeps whichever non-nil list was set.

The conflict is only reachable through a user's `grouping_rules` block, so it is always a config error. Raising is better than the silent first-wins that Ruby's `Hash` would otherwise give us.

- [ ] **Step 1: Write the failing test**

```ruby
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
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e 'percentile conflicts'`
Expected: FAIL with "expected ArgumentError but nothing was raised".

- [ ] **Step 3: Write minimal implementation**

In `group_issues`, inside the `completed_issues.each` loop, replace the accumulate line:

```ruby
(result[rules] ||= []) << issue
```

with a version that reconciles percentiles against the retained key:

```ruby
existing_key = result.keys.find { |key| key.eql? rules }
reconcile_percentiles existing_key, rules if existing_key
(result[existing_key || rules] ||= []) << issue
```

and add:

```ruby
# The retained hash key is whichever rules object arrived first, so a later issue setting a
# different list would silently lose. That can only be a config error, so say so.
def reconcile_percentiles existing_key, rules
  incoming = rules.percentiles
  return if incoming.nil?

  existing = existing_key.percentiles
  if existing.nil?
    existing_key.percentiles = incoming
  elsif existing != incoming
    raise ArgumentError,
      "group #{existing_key.label.inspect} was given conflicting percentiles: " \
      "#{existing.inspect} and #{incoming.inspect}"
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec`
Expected: PASS, all 1851+ examples. `group_issues` is shared with other charts, so a full run matters here rather than a single file.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/groupable_issue_chart.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Reconcile per-group percentiles and raise on conflict

Ruby's Hash keeps the first key, so without this a second issue setting a
different list would be silently ignored."
```

---

### Task 5: Build the annotation data from the configured percentiles

Rewires `run` and `create_datasets` to emit one entry per percentile. This is the task that makes the feature visible.

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb:27-63`
- Test: `spec/cycletime_scatterplot_spec.rb:63-89` (the existing `creates datasets` example changes)

**Interfaces:**
- Consumes: `#percentiles` (Task 2), `#percentile_lines_for` (Task 3), `GroupingRules#percentiles` (Task 1).
- Produces: `@percentage_lines` as an Array of Hashes with keys `percentile`, `value`, `color`, `id`, and `group_label`. `id` is the annotation id used by the ERB and the legend map. `group_label` is `nil` for overall lines.

- [ ] **Step 1: Write the failing test**

```ruby
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
end
```

Note the last example asserts on `percentage_lines` via a public reader, not by reaching into the ivar.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e 'percentage lines'`
Expected: FAIL. The first example should PASS already (it encodes today's behaviour); the second fails with `expected: "Story (50% at 81 days, 85% at 81 days)", got: "Story (85% at 81 days)"`.

- [ ] **Step 3: Write minimal implementation**

Add `attr_reader :percentage_lines` alongside the existing `attr_reader :y_axis_cap_percentile`.

Replace `run` lines 27-39 and `create_datasets` lines 41-63:

```ruby
def run
  items = all_items
  data_sets = create_datasets items
  overall_color = CssVariable['--cycletime-scatterplot-overall-trendline-color']

  # Still needed by the description text, which Task 8 templates. Remove it there, not here,
  # so this task leaves a working chart behind.
  overall_percent_line = calculate_percent_line(items) # rubocop:disable Lint/UselessAssignment

  percentile_lines_for(items, @percentiles).each do |percentile, value|
    @percentage_lines << {
      percentile: percentile, value: value, color: overall_color,
      id: "overall_#{percentile}", group_label: nil
    }
  end

  if data_sets.empty?
    return "<h1 class='foldable'>#{@header_text}</h1>" \
      '<div>No data matched the selected criteria. Nothing to show.</div>'
  end

  wrap_and_render(binding, __FILE__)
end

def create_datasets items
  @cap = compute_cap items
  data_sets = []

  group_issues(items).each_with_index do |(rules, items_by_type), group_index|
    label = rules.label
    color = rules.color
    lines = percentile_lines_for items_by_type, (rules.percentiles || @percentiles)
    data = items_by_type.filter_map { |item| data_for_item(item, rules: rules) }
    data_sets << {
      label: percentile_label(label, lines),
      data: data,
      fill: false,
      showLine: false,
      backgroundColor: color
    }

    data_sets << trend_line_data_set(label: label, data: data, color: color)

    lines.each do |percentile, value|
      @percentage_lines << {
        percentile: percentile, value: value, color: color,
        id: "group#{group_index}_#{percentile}", group_label: label
      }
    end
  end
  data_sets
end

# "Story (85% at 81 days)" for one, comma separated for several, bare label for none.
def percentile_label label, lines
  return label if lines.empty?

  parts = lines.collect { |percentile, value| "#{percentile}% at #{label_days value}" }
  "#{label} (#{parts.join ', '})"
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec`
Expected: PASS. The existing `creates datasets` example at `spec/cycletime_scatterplot_spec.rb:63` must still pass unchanged, proving the byte-identical guarantee for the default config.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Draw one percentile line per configured percentile

The default of [85] reproduces the previous single line and legend text
exactly."
```

---

### Task 6: Render the annotations with hover labels

**Files:**
- Modify: `lib/jirametrics/html/time_based_scatterplot.erb:132-142`
- Test: manual render plus the JS test suite (`rake test_js`)

**Interfaces:**
- Consumes: `@percentage_lines` entries from Task 5.
- Produces: annotations keyed by each entry's `id` rather than `line<index>`.

`hitTolerance: 6` is required. The plugin computes its hit area as `(borderWidth + hitTolerance) / 2`; with `borderWidth: 1` and the default `hitTolerance: 0` the target is 0.5px and hovering is effectively impossible. Verified against the `v3.1.0` tag.

- [ ] **Step 1: Replace the annotation loop**

```erb
          <% @percentage_lines.each do |line| %>
          <%= line[:id] %>: {
            type: 'line',
            yMin: <%= line[:value] %>,
            yMax: <%= line[:value] %>,
            borderColor: <%= line[:color].to_json %>,
            borderWidth: 1,
            hitTolerance: 6,
            drawTime: 'beforeDraw',
            label: {
              display: false,
              content: '<%= line[:percentile] %>% at <%= label_days line[:value] %>',
              position: 'end',
              backgroundColor: 'rgba(0,0,0,0.85)',
              color: '#fff',
              font: { size: 11 }
            },
            enter(ctx) { ctx.element.label.options.display = true; ctx.chart.draw(); },
            leave(ctx) { ctx.element.label.options.display = false; ctx.chart.draw(); }
          },
          <% end %>
```

- [ ] **Step 2: Add the interaction option**

In the same `annotation:` block, as a sibling of `annotations:`, add:

```erb
        interaction: { intersect: false },
```

This makes hover pick the nearest annotation rather than requiring an exact hit, which compounds with `hitTolerance` for a comfortable target.

- [ ] **Step 3: Verify a real report renders and hovers**

Generate a report against real data (`rake export`) and open it. Confirm: the 85% line appears where it did before, hovering it reveals `85% at N days`, and the label disappears on leave. Then set `percentiles [50, 85, 98]` in the config and confirm three lines per group appear with distinct hover labels.

This step is manual and cannot be automated here. Do not mark it complete without actually looking at a rendered chart.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rspec && rake test_js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/html/time_based_scatterplot.erb && \
git commit -m "Render percentile lines with hover labels

hitTolerance is required: the plugin's hit area is (borderWidth +
hitTolerance) / 2, so a 1px line is unhoverable at the default of 0."
```

---

### Task 7: Rewire the legend toggle

The riskiest change. `erb:155` currently does `annotations["line"+(i/2)]`, assuming datasets come in pairs and each group owns exactly one annotation. The second assumption is now false.

**Files:**
- Modify: `lib/jirametrics/html/time_based_scatterplot.erb:145-163`
- Modify: `lib/jirametrics/time_based_scatterplot.rb` (add the map builder)

**Interfaces:**
- Consumes: `@percentage_lines` entries from Task 5, each carrying `group_label` and `id`.
- Produces: `#legend_annotation_map` returning `Hash<String, Array<String>>`, group label to annotation ids. Overall lines are excluded, so toggling a group never hides them.

- [ ] **Step 1: Write the failing test**

```ruby
describe '#legend_annotation_map' do
  let(:board) { load_complete_sample_board }
  let(:issue) { load_issue('SP-10', board: board) }

  before do
    board.cycletime = default_cycletime_config
    chart.issues = [issue]
  end

  it 'maps a group label to its own annotation ids' do
    chart.percentiles [50, 85]
    chart.create_datasets [issue]
    expect(chart.legend_annotation_map).to eq({ 'Story' => %w[group0_50 group0_85] })
  end

  it 'excludes overall lines so they survive a group toggle' do
    allow(chart).to receive(:wrap_and_render).and_return('')
    chart.run
    expect(chart.legend_annotation_map.values.flatten).not_to include 'overall_85'
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#legend_annotation_map'`
Expected: FAIL with `NoMethodError`, then a genuine assertion failure once a stub returning `{}` exists.

- [ ] **Step 3: Write minimal implementation**

```ruby
# Group label to the annotation ids belonging to that group, so the legend handler can toggle
# all of a group's lines. Overall lines are deliberately absent; they are not owned by any
# group and stay visible when a group is switched off.
def legend_annotation_map
  @percentage_lines.reject { |line| line[:group_label].nil? }
    .group_by { |line| line[:group_label] }
    .transform_values { |lines| lines.collect { |line| line[:id] } }
end
```

- [ ] **Step 4: Replace the JavaScript handler**

In the ERB, replace the single-annotation line with a lookup driven by the map:

```erb
        onClick: (evt, legendItem, legend) => {
          // Find the datasetMeta that corresponds to the item clicked
          var i = 0
          while(legendItem.text != legend.chart.getDatasetMeta(i).label) {
            i++;
          }
          nextVisibility = !!legend.chart.getDatasetMeta(i).hidden;

          // Hide/show every percentile line belonging to this group. The map is keyed by the
          // group's label rather than computed from the dataset index, because a group can own
          // any number of lines.
          const annotationMap = <%= legend_annotation_map.to_json %>;
          const groupLabel = legendItem.text.replace(/ \(.*\)$/, '');
          (annotationMap[groupLabel] || []).forEach((id) => {
            legend.chart.options.plugins.annotation.annotations[id].display = nextVisibility;
          });
```

Leave the trendline toggle and the default-behaviour call below it untouched.

Note the label regex: the legend text carries the parenthetical from Task 5, so it must be stripped to recover the bare group label used as the map key.

- [ ] **Step 5: Run tests and verify in a browser**

Run: `bundle exec rspec && rake test_js`
Expected: PASS

Then in a rendered report with `percentiles [50, 85]`, click a legend entry and confirm both of that group's lines disappear together while the overall lines stay.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/time_based_scatterplot.rb lib/jirametrics/html/time_based_scatterplot.erb && \
git commit -m "Drive the legend toggle from an explicit annotation map

The old index arithmetic assumed one line per group, which stops being
true once percentiles are configurable."
```

---

### Task 8: Template the description prose

**Files:**
- Modify: `lib/jirametrics/cycletime_scatterplot.rb:12-26`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `@percentage_lines` from Task 5 (the overall entries, where `group_label` is `nil`).
- Produces: `#percentile_description` returning an HTML String, empty when no percentiles are configured.

**Critical timing constraint.** `description_text` is stored as a raw string during
`initialize` and only ERB-rendered later, at `chart_base.rb:69`, against `run`'s binding. So
`#{...}` inside the heredoc evaluates at construction time, BEFORE the user's config block runs,
while `<%= ... %>` evaluates at render time. Percentiles are set by the config block, so the
call MUST be `<%= percentile_description %>`. Using `#{percentile_description}` would silently
freeze the default `[85]` into every report regardless of configuration.

Because the returned string is not itself re-run through ERB, `percentile_description` must
interpolate its values directly rather than emitting `<%= %>`. It sources them from
`@percentage_lines`, which `run` has already populated by then. The local variable
`overall_percent_line` (`time_based_scatterplot.rb:30`) therefore disappears; it is referenced
nowhere else.

- [ ] **Step 1: Write the failing test**

Each example populates `@percentage_lines` through the public API first, because the
description reads the computed lines rather than recomputing them.

```ruby
describe '#percentile_description' do
  let(:board) { load_complete_sample_board }
  let(:issue) { load_issue('SP-10', board: board) }

  before do
    board.cycletime = default_cycletime_config
    chart.issues = [issue]
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
    chart.run
    expect(chart.percentile_description).to eq ''
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#percentile_description'`
Expected: FAIL with `NoMethodError`, then genuine assertion failures once a stub returning `''` exists.

- [ ] **Step 3: Write minimal implementation**

Replace the hardcoded second paragraph of `description_text` with the single ERB tag
`<%= percentile_description %>`, leaving the first paragraph and `#{describe_non_working_days}`
untouched. Then add to `cycletime_scatterplot.rb`:

```ruby
# The prose follows the configuration. With one percentile we keep the original "proxy for
# most" framing; with several that framing makes no sense, and with none there is nothing to
# describe. Values come from @percentage_lines because run has already computed them, and
# because this string is not run through ERB a second time.
def percentile_description
  overall = percentage_lines.select { |line| line[:group_label].nil? }
  return '' if overall.empty?

  overall.size == 1 ? single_percentile_description(overall.first) : multi_percentile_description(overall)
end

def single_percentile_description line
  percentile = line[:percentile]
  days = line[:value]
  <<-HTML
    <div class="p">
      The #{color_block '--cycletime-scatterplot-overall-trendline-color'} line indicates the
      #{percentile}th percentile (#{days} days). #{percentile}% of all
      items on this chart fall on or below the line and the remaining #{100 - percentile}% are
      above the line. #{percentile}% is a reasonable proxy for "most" so that we can say that
      based on this data set, we can predict that most work of this type will complete in
      #{days} days or less. The other lines reflect the #{percentile}% line for that
      respective type of work.
    </div>
  HTML
end

def multi_percentile_description lines
  described = lines.collect { |line| "#{line[:percentile]}th at #{label_days line[:value]}" }
  <<-HTML
    <div class="p">
      The #{color_block '--cycletime-scatterplot-overall-trendline-color'} lines indicate the
      #{described.join ', '} percentiles across all items on this chart. If a line sits at N
      days then that percentage of items completed in N days or less. The same percentiles are
      drawn for each type of work in that type's own colour. Hover any line to see its value.
    </div>
  HTML
end
```

Now delete the `overall_percent_line` local that Task 5 deliberately kept alive, along with its
`rubocop:disable Lint/UselessAssignment` comment. This description was its only consumer.

Then delete `calculate_percent_line` entirely. Task 3 kept it as a bridge, but with the
description no longer using it nothing in production calls it, and a method hardcoding 85 that
exists only to satisfy a test is dead code. Repoint the cap invariant test at the primitive it
actually cares about, `spec/cycletime_scatterplot_spec.rb:250-256`:

```ruby
it 'computes the same 85% line with capping on and off' do
  uncapped = chart.percentile_value(issues, 85)
  chart.cap_y_axis percentile: 90
  capped = chart.percentile_value(issues, 85)
  expect(capped).to eq uncapped
end
```

The invariant under test is unchanged: percentile values are computed from the full data set,
never from capped display values.

- [ ] **Step 4: Verify the default prose is unchanged**

Run: `bundle exec rspec`
Expected: PASS. Diff the rendered description for a default config against the previous output and confirm it is identical.

- [ ] **Step 5: Fix the stale JS comments**

In `lib/jirametrics/html/time_based_scatterplot.erb` and `lib/jirametrics/html/flow_efficiency_scatterplot.erb`, reword the comment "Hide/show the 85% line for that dataset" to "Hide/show the percentile lines for that dataset".

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop && \
git add lib/jirametrics/cycletime_scatterplot.rb lib/jirametrics/html/*.erb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Template the scatterplot description from the configured percentiles

Includes the derived complement, and emits nothing when the lines are off."
```

---

### Task 9: User documentation

**Files:**
- Modify: `../jekyll_jirametrics/config_charts.md`
- Modify: `../jekyll_jirametrics/changes.md`

This is a separate repository. Commit and push it separately from the code repo.

- [ ] **Step 1: Document the setter**

Add a section to `config_charts.md` covering: `percentiles [50, 85, 98]` at chart level, `rule.percentiles` inside `grouping_rules` as a per-group override, `[]` to switch lines off, the default of `[85]`, and that hovering a line shows its value. Note explicitly that the chart-level value drives both the overall lines and the per-group default.

- [ ] **Step 2: Fix the stale reference**

`config_charts.md:142` currently reads "the percentile lines (such as the 85% line) are always calculated from the full data set". Reword so it refers to the configured percentiles rather than naming 85, keeping the full-data-set guarantee intact.

- [ ] **Step 3: Add a changelog entry**

Add to `changes.md` under the current unreleased section, describing the new setter, the per-group override, the empty list, and that the default is unchanged.

- [ ] **Step 4: Commit and push the docs repo**

```bash
cd ../jekyll_jirametrics && \
git add config_charts.md changes.md && \
git commit -m "Document configurable scatterplot percentiles" && \
git push
```

---

### Task 10: Close out

- [ ] **Step 1: Full quality gate**

```bash
bundle exec rspec && rake test_js && bundle exec rubocop
```
Expected: 0 failures, 0 offenses.

- [ ] **Step 2: Update the bead**

`jirametrics-4ad` covers the whole 85% footprint, of which this slice is the scatterplot portion. Do not close it. Update its description to record that the scatterplot is done and which sites remain: the aging bar chart percent line, the board movement forecast, the WIP-by-column recommendation, and the aging WIP CSS variable fallback.

- [ ] **Step 3: File the follow-up bead**

File a new bead for the unpinned `chart.js` CDN reference at `lib/jirametrics/html/index.erb:7`, which serves whatever version is current at render time while the annotation plugin beside it is pinned to 3.1.0. Note that this slice now depends on plugin behaviour (`hitTolerance`, `enter`/`leave`), which raises the cost of an unannounced Chart.js major bump.

- [ ] **Step 4: Push**

```bash
git pull --rebase && bd dolt push && git push && git status -sb
```
Expected: `## main...origin/main` with no ahead marker.
