# CFD Flow Metrics Overlay Design

## Overview

Add an opt-in `show_flow_metrics` feature to `CumulativeFlowDiagram` that teaches users how to read a CFD by overlaying:

1. **Arrival rate line** — linear regression trend line across the full chart showing how fast work enters the system
2. **Departure rate line** — linear regression trend line showing how fast work leaves
3. **Interactive Little's Law triangle** — follows the mouse, showing WIP, approximate average cycle time, and throughput at any point in time, with values labelled inline on each side of the triangle

**Assumption:** `show_flow_metrics` assumes the rightmost active column represents completed work (departures). If the user has ignored the rightmost column via `column_rules`, the metrics will be meaningless. This interaction is not validated — it is a documented limitation.

---

## Section 1: DSL

Add a no-argument `show_flow_metrics` method to `CumulativeFlowDiagram`. Calling it enables the overlay; omitting it (the default) leaves the chart unchanged. `@show_flow_metrics` defaults to `nil`, which the ERB treats as falsy.

```ruby
cumulative_flow_diagram do
  show_flow_metrics
end
```

The method sets `@show_flow_metrics = true`. This flag is available to the ERB template via the existing `binding`-based rendering (`wrap_and_render`).

---

## Section 2: Ruby changes

**File:** `lib/jirametrics/cumulative_flow_diagram.rb`

Add to the public interface (before `def run`):

```ruby
def show_flow_metrics
  @show_flow_metrics = true
end
```

No other Ruby changes. All logic lives in the ERB template's JavaScript plugin.

---

## Section 3: ERB template changes

**File:** `lib/jirametrics/html/cumulative_flow_diagram.erb`

Conditionally render a `cfdFlowMetricsPlugin` inside the IIFE when `@show_flow_metrics` is true. The plugin is added to the `plugins:` array alongside `cfdHatchPlugin`.

### 3.1 Data model (JavaScript)

The chart datasets store marginal band heights. These look like daily increments but are actually cumulative snapshots with a specific mathematical property:

- For all columns except the last: `marginal[i] = cumulative[i] - cumulative[i+1]`
- For the last column (done): `marginal[last] = cumulative[last]` (no column to its right)

Because datasets are reversed (done = index 0), `datasets[0].data[j].y` is the done column's marginal, which equals its cumulative count. **Departures are therefore directly readable from `datasets[0].data[j].y` without any summation.**

For arrivals, the sum of all marginals telescopes:

```
(cum[0]-cum[1]) + (cum[1]-cum[2]) + ... + (cum[N-2]-cum[N-1]) + cum[N-1] = cum[0]
```

So cumulative arrivals at index `j` = sum of all dataset y values at `j`:

```js
arrivals[j] = datasets.reduce((sum, ds) => sum + (ds.data[j]?.y || 0), 0)
departures[j] = datasets[0].data[j]?.y || 0
```

Both `arrivals[j]` and `departures[j]` are cumulative totals. Note: `departures[j]` is not guaranteed to be monotonically non-decreasing — correction windows (backward movements) can cause the done count to dip on some days. The `j_c` search (Section 3.5) handles this correctly because it scans forward looking for the first crossing, regardless of non-monotonicity.

### 3.2 Plugin structure

```js
const cfdFlowMetricsPlugin = {
  id: 'cfdFlowMetrics',

  afterInit(chart) {
    // Compute and cache regression lines once
    chart._flowMetrics = { mouseX: null, ...computeRegressionLines(chart) };
  },

  afterEvent(chart, args) {
    const fm = chart._flowMetrics;
    const ca = chart.chartArea;
    const { type, x, y } = args.event;
    if (type === 'mousemove' && x >= ca.left && x <= ca.right && y >= ca.top && y <= ca.bottom) {
      if (fm.mouseX !== x) { fm.mouseX = x; args.changed = true; }
    } else if (type === 'mouseout' || type === 'mousemove') {
      if (fm.mouseX !== null) { fm.mouseX = null; args.changed = true; }
    }
  },

  afterDraw(chart) {
    const fm = chart._flowMetrics;
    drawTrendLines(chart, fm);
    if (fm.mouseX !== null) drawTriangle(chart, fm);
  }
};
```

`args.changed = true` is the Chart.js mechanism for requesting a redraw from within `afterEvent` without calling `chart.update()` recursively.

### 3.3 Linear regression

Computed once in `afterInit` over all data points (daily frequency). To avoid floating-point instability from large millisecond timestamps, normalise `x` to day indices (0, 1, 2, …) before computing:

```js
function linearRegression(yValues) {
  const n = yValues.length;
  const sumX  = n * (n - 1) / 2;           // sum of 0..n-1
  const sumX2 = n * (n - 1) * (2*n - 1) / 6;
  const sumY  = yValues.reduce((s, y) => s + y, 0);
  const sumXY = yValues.reduce((s, y, i) => s + i * y, 0);
  const denom = n * sumX2 - sumX * sumX;
  if (denom === 0) return { slope: 0, intercept: sumY / n };
  const slope = (n * sumXY - sumX * sumY) / denom;
  const intercept = (sumY - slope * sumX) / n;
  return { slope, intercept };  // y = slope * dayIndex + intercept
}
```

`computeRegressionLines` builds `arrivalValues` and `departureValues` arrays (indexed 0…n-1) and calls `linearRegression` for each.

To convert a day index back to a pixel x: `chart.scales.x.getPixelForValue(new Date(datasets[0].data[i].x).getTime())`.

### 3.4 Trend lines

Drawn in `afterDraw` across the full chart area using the cached regression. For each regression, compute the y-value at day index 0 and day index `n-1`, convert both to pixels, clamp to the chart area, and draw a line between them.

- Arrival trend line: warm dashed stroke (e.g. `rgba(255, 138, 101, 0.85)`, `[6, 4]`, 1.5px)
- Departure trend line: cool dashed stroke (e.g. `rgba(128, 203, 196, 0.85)`, `[6, 4]`, 1.5px)
- Label at the right edge of each line: "Arrivals" / "Departures" in matching colour, 11px font

### 3.5 Triangle geometry

**Finding data index `j` from cursor pixel:**

```js
const cursorMs = chart.scales.x.getValueForPixel(fm.mouseX); // millisecond timestamp
// find j = index of the dataset date closest to cursorMs
const dates = chart.data.datasets[0].data.map(d => new Date(d.x).getTime());
let j = dates.reduce((best, t, i) =>
  Math.abs(t - cursorMs) < Math.abs(dates[best] - cursorMs) ? i : best, 0);
```

**Three points (computed in data space, converted to pixels):**

| Point | x (data) | y (data) | Notes |
|-------|----------|----------|-------|
| A | `dates[j]` | `arrivals[j]` | top of stack at cursor |
| B | `dates[j]` | `departures[j]` | top of done band at cursor |
| C | `dates[j_c]` | `arrivals[j]` | same y as A |

`j_c` = first index > `j` where `departures[j_c] >= arrivals[j]`. Here `arrivals[j]` is a **fixed threshold** evaluated once at the cursor index `j`; the scan increments only the index used to look up `departures`. Do not re-evaluate `arrivals` at each candidate index.

**Metrics derived:**
- **WIP** = `arrivals[j] - departures[j]` (integer items)
- **Cycle time** = `j_c - j` days
- **Throughput** = `WIP / cycleTime` items/day (two decimal places)

**Guard:** if `WIP === 0` (arrivals[j] equals departures[j]), skip drawing the triangle and all labels entirely. Show only the trend lines.

Pixel conversion:
```js
const xA = chart.scales.x.getPixelForValue(dates[j]);
const yA = chart.scales.y.getPixelForValue(arrivals[j]);
const yB = chart.scales.y.getPixelForValue(departures[j]);
const xC = j_c < n ? chart.scales.x.getPixelForValue(dates[j_c]) : null;
```

### 3.6 Triangle rendering

Draw three segments using canvas `ctx`:

| Segment | From → To | Style | Label text | Label position |
|---------|-----------|-------|------------|----------------|
| AB | A → B | solid white, 2px | `"WIP: N"` | Left of AB midpoint, right-aligned |
| AC | A → C | solid white, 2px | `"~N days"` | Above AC midpoint, centred |
| BC | B → C | dashed white `[4,2]`, 1.5px | `"N.NN/day"` | Below BC midpoint, centred |

BC is dashed because it is a derived line, not directly readable from the chart.

Labels: white, 11px sans-serif, with a small semi-transparent dark background rect for legibility over coloured bands.

**Triangle fill:** before drawing strokes, fill the triangle ABC with `rgba(255, 255, 255, 0.06)`.

**Edge case — C outside date range:** if no `j_c` is found within the dataset, draw AB normally, then extend AC horizontally (constant y = A's y-pixel) to the right edge of the chart area as a dashed line. Omit the BC segment, triangle fill, and throughput label entirely.

### 3.7 No JavaScript unit tests

The `linearRegression` function is pure but the spec intentionally omits Jest tests for it — the entire plugin is visual/interactive and is best verified manually. An implementer who wants to add a Jest test for the regression function may do so but it is not required.

---

## Section 4: Testing

**File:** `spec/cumulative_flow_diagram_spec.rb`

Add a new `context 'show_flow_metrics'` block **nested inside the existing `context 'column_rules'`** (which defines the `chart_with_rules` helper needed by these tests):

```ruby
context 'show_flow_metrics' do
  it 'does not include flow metrics plugin by default' do
    output = chart_with_rules {}.run
    expect(output).not_to include('cfdFlowMetrics')
  end

  it 'includes flow metrics plugin when show_flow_metrics is called' do
    output = chart_with_rules { show_flow_metrics }.run
    expect(output).to include('cfdFlowMetrics')
  end
end
```

---

## Section 5: Files summary

| File | Change |
|------|--------|
| `lib/jirametrics/cumulative_flow_diagram.rb` | Add `show_flow_metrics` method |
| `lib/jirametrics/html/cumulative_flow_diagram.erb` | Conditional `cfdFlowMetricsPlugin` block |
| `spec/cumulative_flow_diagram_spec.rb` | Two new tests nested inside `context 'column_rules'` |
