# Scatterplot Y-Axis Cap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the time based scatterplot family cap its y-axis at a chosen percentile so outliers stop crushing the readable data, moving over-cap items into a visually distinct gutter above an axis break instead of dropping them.

**Architecture:** A new opt-in `cap_y_axis percentile:` setter on `TimeBasedScatterplot`. The cap value and layout are computed in Ruby from the full item set (a shared `percentile_value` helper also backs the existing 85% line). Over-cap points are flagged and remapped to a pinned row in `data_for_item`. The ERB template renders the gutter band, a pixel-drawn hairline double rule, a count label, and per-point up-arrow markers, all only when capping is active and outliers exist. Statistics (85% lines, trend lines) always use the full data.

**Tech Stack:** Ruby, RSpec, RuboCop, ERB templates, Chart.js (with the annotation plugin), CSS custom properties for theming.

## Global Constraints

- Ruby project. Tests: `bundle exec rspec`. Linter: `bundle exec rubocop` (must be zero offenses on touched files; gate the commit on its exit code).
- Do NOT modify Data Centre code (deprecated).
- Feature is opt-in: with no `cap_y_axis` call, output is byte-for-byte unchanged from today.
- Default percentile when `cap_y_axis` is called with no argument: **98**.
- The keyword is singular `percentile:`, deliberately distinct from the existing plural `percentiles [...]` lines setter.
- Statistics invariant: the 85% percentile lines and trend lines are always computed from the full (min-filtered) item set, never the visible subset.
- Prose and comments: no em-dashes. Use snake_case for Ruby hash keys. Descriptive variable names, never single-letter. Group independent assertions in `aggregate_failures do ... end` blocks.
- Trunk-based: commit directly to `main`.
- User-facing DSL: update the Jekyll docs repo `../jekyll_jirametrics` (config reference + `changes.md`) as part of shipping (Task 6).

---

## File Structure

- `lib/jirametrics/time_based_scatterplot.rb` — the setter, the shared `percentile_value` helper, `compute_cap`, point remapping in `data_for_item`, trend-line clamp. Most Ruby logic lives here because both scatterplots inherit it.
- `lib/jirametrics/html/time_based_scatterplot.erb` — all rendering: axis max, tick suppression, gutter box, double-rule plugin, count label, up-arrow post-processing.
- `lib/jirametrics/html/index.css` — two new theme variables for the rule and gutter colours (light block, `.dark-mode` block, and the `@media (prefers-color-scheme: dark)` block).
- `spec/cycletime_scatterplot_spec.rb` — Ruby-level tests (the concrete subclass with a real sample board).
- `../jekyll_jirametrics` — user documentation (Task 6).

---

### Task 1: `cap_y_axis` config setter

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Produces: `cap_y_axis(percentile: 98)` sets `@y_axis_cap_percentile`; returns the stored percentile. Never called leaves it `nil` (disabled). Reader `y_axis_cap_percentile` for tests.

- [ ] **Step 1: Write the failing test**

Add to `spec/cycletime_scatterplot_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#cap_y_axis'`
Expected: FAIL at the assertion (`NoMethodError` on `y_axis_cap_percentile` means add the reader first, then re-run so the assertion is what fails).

- [ ] **Step 3: Write minimal implementation**

In `lib/jirametrics/time_based_scatterplot.rb`, add the reader to the existing `attr_accessor` area and the setter:

```ruby
attr_reader :y_axis_cap_percentile

def cap_y_axis percentile: 98
  @y_axis_cap_percentile = percentile
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#cap_y_axis'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Add cap_y_axis setter to time based scatterplot"
```

---

### Task 2: Shared `percentile_value` and `compute_cap`

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `y_axis_cap_percentile` (Task 1); `minimum_y_value`; `y_value(item)`.
- Produces:
  - `percentile_value(items, percentile)` returns the value at that percentile of `y_value`, min-filtered. Returns `nil` for an empty set.
  - `compute_cap(items)` returns a hash `{ cutoff:, sep:, pin_row:, axis_max:, outlier_count: }` when capping is enabled AND at least one item exceeds the cutoff; otherwise `nil`.
  - `calculate_percent_line(items)` is refactored to call `percentile_value(items, 85)` with identical results.

- [ ] **Step 1: Write the failing test**

`compute_cap` and `percentile_value` are numeric over `y_value`, so drive them with plain doubles and a stubbed `y_value`. Add to `spec/cycletime_scatterplot_spec.rb`:

```ruby
describe '#percentile_value' do
  it 'returns the value at the requested percentile, min-filtered' do
    items = Array.new(20) { |index| "item#{index}" }
    values = (1..19).to_a + [500] # 20 values; index 20*85/100 = 17 -> sorted[17] = 18
    allow(chart).to receive(:y_value) { |item| values[items.index(item)] }
    expect(chart.percentile_value(items, 85)).to eq 18
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
    chart.cap_y_axis percentile: 85 # cutoff = 18, so only the 500 is over
    cap = chart.compute_cap(items)
    aggregate_failures do
      expect(cap[:cutoff]).to eq 18
      expect(cap[:outlier_count]).to eq 1
      expect(cap[:sep]).to be_within(0.001).of(18 + (18 * 0.06))
      expect(cap[:axis_max]).to eq (18 + (18 * 0.06) + (18 * 0.15)).ceil
      expect(cap[:pin_row]).to be_within(0.001).of((18 + (18 * 0.06)) + (18 * 0.15 * 0.55))
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e '#compute_cap' -e '#percentile_value'`
Expected: FAIL at assertions (methods do not yet exist; add skeletons returning `nil` if you want a clean assertion-level red first).

- [ ] **Step 3: Write minimal implementation**

In `lib/jirametrics/time_based_scatterplot.rb`, replace `calculate_percent_line` and add the two methods:

```ruby
def calculate_percent_line items
  percentile_value items, 85
end

def percentile_value items, percentile
  min = minimum_y_value
  values = items.collect { |item| y_value(item) }
  values.reject! { |value| min && value < min }
  return nil if values.empty?

  index = [values.size * percentile / 100, values.size - 1].min
  values.sort[index]
end

def compute_cap items
  return nil unless @y_axis_cap_percentile

  cutoff = percentile_value items, @y_axis_cap_percentile
  return nil if cutoff.nil?

  min = minimum_y_value
  values = items.collect { |item| y_value(item) }.reject { |value| min && value < min }
  outlier_count = values.count { |value| value > cutoff }
  return nil if outlier_count.zero?

  pad = cutoff * 0.06        # breathing room so the top real dot does not touch the break
  gutter_height = cutoff * 0.15
  sep = cutoff + pad
  {
    cutoff: cutoff,
    sep: sep,
    pin_row: sep + (gutter_height * 0.55),
    axis_max: (sep + gutter_height).ceil,
    outlier_count: outlier_count
  }
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb`
Expected: PASS (including the existing `creates datasets` / `Story (85% at 81 days)` characterization test, proving the `calculate_percent_line` refactor is behaviour-preserving).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Add percentile_value and compute_cap; back 85% line with percentile_value"
```

---

### Task 3: Remap over-cap points and clamp the trend line

**Files:**
- Modify: `lib/jirametrics/time_based_scatterplot.rb`
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `compute_cap(items)` (Task 2).
- Produces:
  - `create_datasets(items)` sets `@cap = compute_cap(items)` before building points (so `run` and the template can read `@cap`).
  - `data_for_item` reads `@cap`: when set and `y_value > @cap[:cutoff]`, the point's `y` is `@cap[:pin_row]` and the point gains `over: true`; the true cycletime already lives in the existing `title`. Otherwise the point is unchanged.
  - `trend_line_data_set` uses `max_y: (@cap ? @cap[:cutoff] : @highest_y_value)`.

- [ ] **Step 1: Write the failing test**

The cleanest public surface is `create_datasets`, which already returns the datasets. Add to `spec/cycletime_scatterplot_spec.rb`. This uses the real sample board issue (SP-10 = 81 days) and a cap low enough to force it over:

```ruby
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
    chart.cap_y_axis percentile: 50 # a single item: cutoff = 81, nothing over
    chart.cap_y_axis percentile: 1  # force the cutoff below 81 so the point is over
    scatter = chart.create_datasets([issue]).first
    point = scatter[:data].first
    cap = chart.compute_cap([issue])
    aggregate_failures do
      expect(point[:over]).to be true
      expect(point[:y]).to eq cap[:pin_row]
      expect(point[:title]).to eq ['SP-10 : Check in people at an event (81 days)']
    end
  end
end
```

Note: with a single item, `percentile_value` returns that item's value as the cutoff and nothing is "over", so a single-issue over-cap case needs the cutoff strictly below the value. Percentile 1 on one item gives index 0 = the value itself, which is not `> cutoff`. If a single-item over case proves impossible to construct through the percentile, use two issues (load `SP-1` alongside `SP-10`) so one lands above the cutoff. Adjust the fixture to whichever the sample board supports; assert the same three facts.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e 'capping in create_datasets'`
Expected: FAIL at the `over`/`pin_row` assertions.

- [ ] **Step 3: Write minimal implementation**

In `lib/jirametrics/time_based_scatterplot.rb`:

At the top of `create_datasets`, before the loop:

```ruby
def create_datasets items
  @cap = compute_cap items
  data_sets = []
  # ... existing body unchanged ...
```

Replace `data_for_item`:

```ruby
def data_for_item item, rules: nil
  y = y_value(item)
  min = minimum_y_value
  return nil if min && y < min

  over = @cap && y > @cap[:cutoff]
  plotted_y = over ? @cap[:pin_row] : y
  @highest_y_value = plotted_y if @highest_y_value < plotted_y

  point = {
    y: plotted_y,
    x: chart_format(x_value(item)),
    title: [title_value(item, rules: rules)]
  }
  point[:over] = true if over
  point
end
```

In `trend_line_data_set`, change the `max_y:` argument:

```ruby
data_points = calculator.chart_datapoints(
  range: time_range.begin.to_i..time_range.end.to_i,
  max_y: (@cap ? @cap[:cutoff] : @highest_y_value)
)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb`
Expected: PASS (existing `creates datasets` test still green: with no cap, `@cap` is nil and points are unchanged).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git add lib/jirametrics/time_based_scatterplot.rb spec/cycletime_scatterplot_spec.rb && \
git commit -m "Remap over-cap scatterplot points to the gutter and clamp the trend line"
```

---

### Task 4: Statistics invariant test

**Files:**
- Test: `spec/cycletime_scatterplot_spec.rb`

**Interfaces:**
- Consumes: `calculate_percent_line` and `create_datasets` (unchanged by capping).

This task adds no production code. It locks in the invariant that capping is a view-only concern.

- [ ] **Step 1: Write the test**

```ruby
describe 'statistics are unaffected by capping' do
  let(:board) { load_complete_sample_board }
  let(:issues) { %w[SP-1 SP-10].map { |key| load_issue(key, board: board) } }

  before { board.cycletime = default_cycletime_config }

  it 'computes the same 85% line with capping on and off' do
    uncapped = chart.calculate_percent_line(issues)
    chart.cap_y_axis percentile: 90
    capped = chart.calculate_percent_line(issues)
    expect(capped).to eq uncapped
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bundle exec rspec spec/cycletime_scatterplot_spec.rb -e 'statistics are unaffected'`
Expected: PASS immediately (this is a guard test; it documents and protects existing behaviour rather than driving new code).

- [ ] **Step 3: Commit**

```bash
git add spec/cycletime_scatterplot_spec.rb && \
git commit -m "Lock in that scatterplot statistics ignore the y-axis cap"
```

---

### Task 5: Render the gutter, double rule, count label, and up-arrows

**Files:**
- Modify: `lib/jirametrics/html/time_based_scatterplot.erb`
- Modify: `lib/jirametrics/html/index.css`
- Verify: the real HTML report in a browser (light and dark)

**Interfaces:**
- Consumes: `@cap` (hash or nil) set by `create_datasets` and available in the template binding; each over-cap point carries `over: true`.

This is the rendering task. It cannot be unit tested (it is Chart.js JS inside ERB); its acceptance is browser verification in both themes.

- [ ] **Step 1: Add theme CSS variables**

In `lib/jirametrics/html/index.css`, add two variables in each of the three colour blocks (the light `:root`, the `.dark-mode` block, and the `@media (prefers-color-scheme: dark)` block), next to the existing `--grid-line-color` entries.

Light block:

```css
--cycletime-scatterplot-cap-rule-color: #555555;
--cycletime-scatterplot-cap-gutter-color: rgba(0, 0, 0, 0.05);
```

Both dark blocks:

```css
--cycletime-scatterplot-cap-rule-color: #b8b8b8;
--cycletime-scatterplot-cap-gutter-color: rgba(255, 255, 255, 0.08);
```

- [ ] **Step 2: Post-process datasets for up-arrow markers**

In `lib/jirametrics/html/time_based_scatterplot.erb`, replace the datasets line inside `data:` :

```erb
    datasets: <%= JSON.generate(data_sets) %>
```

with an IIFE that adds per-point arrow markers when capping is active (scoped so nothing leaks to the page and multiple charts do not collide):

```erb
    datasets: (function() {
      const dataSets = <%= JSON.generate(data_sets) %>;
      <% if @cap %>
      // draw an up-arrow glyph in the given colour, usable as a Chart.js pointStyle.
      // The arrow says "the real value continues upward beyond the cap".
      function capArrow(color) {
        const size = 18, glyph = document.createElement('canvas');
        glyph.width = size; glyph.height = size;
        const pen = glyph.getContext('2d');
        pen.strokeStyle = color; pen.lineWidth = 2.5; pen.lineCap = 'round'; pen.lineJoin = 'round';
        pen.beginPath();
        pen.moveTo(size / 2, size - 3); pen.lineTo(size / 2, 3);
        pen.moveTo(size / 2 - 5, 8); pen.lineTo(size / 2, 3); pen.lineTo(size / 2 + 5, 8);
        pen.stroke();
        return glyph;
      }
      dataSets.forEach(function(dataSet) {
        if (dataSet.type === 'line') return; // skip the interleaved trend lines
        const arrow = capArrow(dataSet.backgroundColor);
        dataSet.pointStyle = dataSet.data.map(function(point) { return point.over ? arrow : 'circle'; });
        dataSet.pointRadius = dataSet.data.map(function(point) { return point.over ? 9 : 3; });
      });
      <% end %>
      return dataSets;
    })()
```

- [ ] **Step 3: Cap the y-axis and suppress ticks above the cutoff**

Replace the `y:` scale's `max` line and the ticks callback. The current template has:

```erb
      y: {
        min: 0,
        max: <%= (@highest_y_value * 1.1).ceil %>,
```

Change `max` to:

```erb
        max: <%= @cap ? @cap[:axis_max] : (@highest_y_value * 1.1).ceil %>,
```

And change the existing ticks callback so that, when capping is active, no tick is drawn above the cutoff:

```erb
        ticks: {
          callback: function(value, index, ticks) {
            <% if @cap %>if (value > <%= @cap[:cutoff] %>) return null;<% end %>
            return index === ticks.length - 1 ? null : value;
          }
        }
```

- [ ] **Step 4: Add the gutter box and count label annotations**

In the `annotation.annotations` object, add (only when `@cap`) the gutter band and the count label. Place alongside the existing `working_days_annotation` / `date_annotation` entries:

```erb
          <% if @cap %>
          capGutter: {
            type: 'box',
            yMin: <%= @cap[:sep] %>,
            yMax: <%= @cap[:axis_max] %>,
            backgroundColor: <%= CssVariable['--cycletime-scatterplot-cap-gutter-color'].to_json %>,
            borderWidth: 0
          },
          capLabel: {
            type: 'line',
            yMin: <%= @cap[:sep] %>,
            yMax: <%= @cap[:sep] %>,
            borderWidth: 0,
            label: {
              display: true,
              content: '<%= @cap[:outlier_count] %> items above <%= @cap[:cutoff] %> days',
              position: 'end',
              yAdjust: -14,
              backgroundColor: 'rgba(0,0,0,0.85)',
              color: '#fff',
              font: { size: 11 }
            }
          },
          <% end %>
```

- [ ] **Step 5: Add the double-rule plugin**

Add a `plugins:` array to the `new Chart(...)` config (a sibling key to `type`, `data`, `options`), only when capping is active. The plugin draws the break in pixel space so the gap stays a hairline at any scale, and reads the rule colour live so it follows the dark-mode toggle:

```erb
new Chart(document.getElementById('<%= chart_id %>').getContext('2d'), {
  type: 'scatter',
  <% if @cap %>
  plugins: [{
    id: 'capRule<%= chart_id %>',
    afterDatasetsDraw: function(chart) {
      const yPixel = chart.scales.y.getPixelForValue(<%= @cap[:sep] %>);
      const area = chart.chartArea;
      const pen = chart.ctx;
      pen.save();
      pen.strokeStyle = <%= CssVariable['--cycletime-scatterplot-cap-rule-color'].to_json %>;
      pen.lineWidth = 1.5;
      [0, 3].forEach(function(offset) {
        pen.beginPath();
        pen.moveTo(area.left, yPixel - offset);
        pen.lineTo(area.right, yPixel - offset);
        pen.stroke();
      });
      pen.restore();
    }
  }],
  <% end %>
  data: {
```

The plugin id is suffixed with `chart_id` so multiple charts on one page register distinct plugins.

- [ ] **Step 6: Verify in a browser (light and dark)**

Generate a report whose cycletime scatterplot config includes `cap_y_axis percentile: 85` (a low percentile makes several outliers visible for checking). Open the rendered HTML and confirm:

- The bulk of the data expands into the readable area below the break.
- The double rule reads as a tight hairline "railroad" separator, constant width, not touching the top real dot.
- Up-arrows sit in the grey gutter in their type colours; hovering one shows the true cycletime via the point title.
- The count label is legible and not crossed by the rule lines.
- No y-axis ticks appear above the cutoff.
- Toggle dark mode: the gutter band stays distinguishable from the plot background and the rule and arrows stay legible.
- Remove `cap_y_axis` from the config and confirm the chart renders exactly as before (no break, gutter, arrows, or label).

- [ ] **Step 7: Commit**

```bash
bundle exec rubocop lib/jirametrics/html/time_based_scatterplot.erb 2>/dev/null; \
git add lib/jirametrics/html/time_based_scatterplot.erb lib/jirametrics/html/index.css && \
git commit -m "Render y-axis cap gutter, double rule, count label, and up-arrow markers"
```

(RuboCop does not lint `.erb`; the command above is harmless if it reports nothing. Ensure the full suite is green: `bundle exec rspec`.)

---

### Task 6: User documentation

**Files:**
- Modify: `../jekyll_jirametrics` (config reference page + `changes.md`)

**Interfaces:** none (docs only).

- [ ] **Step 1: Locate the scatterplot config reference page**

```bash
grep -rln "show_trend_lines\|cycletime_scatterplot\|scatterplot" ../jekyll_jirametrics
```

Use the page that documents scatterplot / chart configuration setters.

- [ ] **Step 2: Document `cap_y_axis`**

Add an entry describing:
- `cap_y_axis percentile: 98` on the cycletime and pull-request cycle-time scatterplots.
- It is opt-in; without it the chart shows all data auto-scaled.
- What it does: caps the y-axis at the given percentile so outliers no longer compress the bulk; over-cap items move to a gutter above an axis break, shown as up-arrows in their type colour, still hoverable for their true value.
- The default is the 98th percentile when no argument is given.
- Statistics (the 85% lines) are unaffected.

- [ ] **Step 3: Add a changelog entry**

Add a `changes.md` entry for the new `cap_y_axis` scatterplot option.

- [ ] **Step 4: Commit (docs repo)**

```bash
cd ../jekyll_jirametrics && git add -A && git commit -m "Document cap_y_axis scatterplot option" && cd -
```

Deployment (`rake deploy`) is the author's call and separate from the code change.

---

## Self-Review

**Spec coverage:**
- Section 1 (DSL) → Task 1.
- Section 2 (statistics invariant) → Task 4, plus the `calculate_percent_line` refactor characterization in Task 2.
- Section 3 (vertical layout) → Task 2 (`compute_cap` constants) + Task 5 (rendering).
- Section 4 (point handling) → Task 3.
- Section 5 (rendering) → Task 5.
- Section 6 (theme) → Task 5 Steps 1, 5, 6.
- Section 7 (edge cases): no outliers → `compute_cap` returns nil (Task 2 test) and template guards on `@cap` (Task 5); empty set → existing `run` short-circuit, untouched; cap below a reference line → documented, no special handling.
- Section 8 (testing) → Tasks 1 to 5.
- Section 9 (user docs) → Task 6.

**Placeholder scan:** Task 3's fixture note is a genuine branch (single vs two issue), not a placeholder; both paths assert the same three facts. No TBD/TODO left.

**Type consistency:** `@cap` hash keys (`:cutoff`, `:sep`, `:pin_row`, `:axis_max`, `:outlier_count`) are used identically in `compute_cap` (Task 2), `data_for_item`/`trend_line_data_set` (Task 3), and the template (Task 5). `percentile_value(items, percentile)` and `compute_cap(items)` signatures match across tasks. `y_axis_cap_percentile` reader is defined in Task 1 and consumed in Task 2.

---

## Execution Handoff

(To be offered after the plan is approved.)
