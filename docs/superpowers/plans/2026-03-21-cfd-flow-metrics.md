# CFD Flow Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `show_flow_metrics` DSL method to `CumulativeFlowDiagram` that overlays arrival/departure trend lines and an interactive Little's Law triangle (WIP, cycle time, throughput) on the CFD.

**Architecture:** One Ruby method sets a flag (`@show_flow_metrics = true`) read by the ERB template. All behaviour lives in a single `cfdFlowMetricsPlugin` Chart.js plugin rendered conditionally in the ERB. The plugin uses `afterInit` to compute linear regression once, `afterEvent` to track the mouse, and `afterDraw` to render the overlay.

**Tech Stack:** Ruby, RSpec, Chart.js (ERB template), canvas 2D API.

---

### Task 1: Add `show_flow_metrics` DSL method

**Files:**
- Modify: `lib/jirametrics/cumulative_flow_diagram.rb`
- Test: `spec/cumulative_flow_diagram_spec.rb`

#### Background

The spec file has a `context 'column_rules'` block (lines 52–123) that defines the `chart_with_rules` helper. The two new tests must be nested **inside** `context 'column_rules'` (before its closing `end` at line 123) so they can use that helper.

The first test checks the default — no `show_flow_metrics` call → no plugin JS in output. The second test calls `show_flow_metrics` inside the DSL block, which goes through `instance_eval` in `initialize`, so the method must be a public instance method on `CumulativeFlowDiagram`.

The identifier `'cfdFlowMetrics'` is the plugin's `id` string that will be present in the ERB output when the flag is set. Task 2 will make the second test pass by adding the ERB plugin.

- [ ] **Step 1: Write the failing tests**

In `spec/cumulative_flow_diagram_spec.rb`, insert the following **before** the closing `end` of `context 'column_rules'` (currently at line 123, after the `'includes the legend hover tooltip plugin...'` test):

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

- [ ] **Step 2: Run the tests to verify they fail**

```bash
rake spec
```

Expected: 1 failure — `NoMethodError: undefined method 'show_flow_metrics'`. The first test ("does not include") may pass immediately since the string is absent by default.

- [ ] **Step 3: Add the `show_flow_metrics` method**

In `lib/jirametrics/cumulative_flow_diagram.rb`, add after `def column_rules &block` / `@column_rules_block = block` / `end` (around line 64), before `def run`:

```ruby
def show_flow_metrics
  @show_flow_metrics = true
end
```

- [ ] **Step 4: Run the tests to verify the first test passes (second still fails)**

```bash
rake spec
```

Expected: 1 failure — `'cfdFlowMetrics'` not found in output. The method now exists so no `NoMethodError`, but the ERB doesn't emit the plugin yet (Task 2 fixes this).

- [ ] **Step 5: Run RuboCop**

```bash
rubocop lib/jirametrics/cumulative_flow_diagram.rb spec/cumulative_flow_diagram_spec.rb
```

Fix any offenses. Ignore the pre-existing `plugins:` warning in `.rubocop.yml`.

---

### Task 2: Implement `cfdFlowMetricsPlugin` in the ERB template

**Files:**
- Modify: `lib/jirametrics/html/cumulative_flow_diagram.erb`

#### Background

The ERB template is inside `<script>` tags. There is already a custom plugin `cfdHatchPlugin` defined inside the IIFE `(function() { ... })()`. The `cfdFlowMetricsPlugin` must also live inside the IIFE and be added to the `plugins:` array in the `new Chart(...)` call.

The `@show_flow_metrics` ivar is accessed in ERB as `<%= @show_flow_metrics %>` or tested with `<% if @show_flow_metrics %>`. When `nil` (default), the `if` is falsy and no plugin code is emitted.

**Data model recap** (important — read before implementing):

- Datasets are in reversed order: done column = `datasets[0]`, leftmost column = `datasets[last]`
- `datasets[0].data[j].y` = cumulative departures at index j. This equals cumulative count because the done column is the rightmost, so its marginal equals its cumulative (no column to its right)
- `arrivals[j]` = sum of all dataset y values at j (marginals telescope to give `cumulative[0]`, the total ever arrived)
- Neither arrivals nor departures are guaranteed monotone (correction windows can cause dips); the j_c forward scan handles this correctly regardless
- `arrivals[j]` is a **fixed threshold** in the j_c scan — do not re-evaluate it per candidate index

**Plugin responsibilities:**

1. `afterInit` — build arrivals/departures arrays, compute linear regression for each, cache on `chart._flowMetrics`
2. `afterEvent` — update `fm.mouseX` on `mousemove` within chart area; clear on `mouseout`. Use `args.changed = true` (not `chart.update()`) to request redraw
3. `afterDraw` — always draw the two trend lines; draw the triangle+labels if `mouseX` is set

**Triangle geometry:**

```
A ————————— C      (same y; horizontal top = cycle time)
|          /
|         /        (dashed hypotenuse = throughput slope)
|        /
B                  (directly below A; vertical left = WIP)
```

- A = (xA, yA): cursor x, top of stack
- B = (xA, yB): cursor x, top of done band (below A)
- C = (xC, yA): first future date where departures ≥ arrivals[j]
- Skip triangle entirely if WIP = 0 (`arrivals[j] === departures[j]`)
- If C is outside the date range, draw AB solid + AC dashed to chart right edge; omit BC and throughput label

- [ ] **Step 1: Add the conditional plugin block inside the IIFE**

In `lib/jirametrics/html/cumulative_flow_diagram.erb`, find the line:

```javascript
  new Chart(document.getElementById('<%= chart_id %>').getContext('2d'), {
```

Insert the following block **immediately before** that line (still inside the IIFE):

```erb
<% if @show_flow_metrics %>
  const cfdFlowMetricsPlugin = (function () {
    function buildArrays(chart) {
      const ds = chart.data.datasets;
      const n = ds[0].data.length;
      const arrivals = [], departures = [];
      for (let j = 0; j < n; j++) {
        arrivals[j]   = ds.reduce((s, d) => s + (d.data[j]?.y || 0), 0);
        departures[j] = ds[0].data[j]?.y || 0;
      }
      return { arrivals, departures };
    }

    function linearRegression(yValues) {
      const n = yValues.length;
      const sumX  = n * (n - 1) / 2;
      const sumX2 = n * (n - 1) * (2 * n - 1) / 6;
      const sumY  = yValues.reduce((s, y) => s + y, 0);
      const sumXY = yValues.reduce((s, y, i) => s + i * y, 0);
      const denom = n * sumX2 - sumX * sumX;
      if (denom === 0) return { slope: 0, intercept: sumY / n };
      return {
        slope:     (n * sumXY - sumX * sumY) / denom,
        intercept: (sumY - (n * sumXY - sumX * sumY) / denom * sumX) / n
      };
    }

    function trendPixelY(chart, reg, dayIndex) {
      return chart.scales.y.getPixelForValue(reg.slope * dayIndex + reg.intercept);
    }

    function drawTrendLines(chart, fm) {
      const ctx = chart.ctx;
      const ca  = chart.chartArea;
      const ds  = chart.data.datasets;
      const n   = ds[0].data.length;
      const x0  = chart.scales.x.getPixelForValue(new Date(ds[0].data[0].x).getTime());
      const x1  = chart.scales.x.getPixelForValue(new Date(ds[0].data[n - 1].x).getTime());

      function drawLine(reg, color) {
        const y0 = trendPixelY(chart, reg, 0);
        const y1 = trendPixelY(chart, reg, n - 1);
        ctx.save();
        ctx.beginPath();
        ctx.rect(ca.left, ca.top, ca.width, ca.height);
        ctx.clip();
        ctx.setLineDash([6, 4]);
        ctx.lineWidth = 1.5;
        ctx.strokeStyle = color;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x1, y1);
        ctx.stroke();
        ctx.restore();
      }

      drawLine(fm.arrivalReg,   'rgba(255,138,101,0.85)');
      drawLine(fm.departureReg, 'rgba(128,203,196,0.85)');

      // Edge labels
      ctx.save();
      ctx.font = '10px sans-serif';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      const labelX = ca.right + 5;
      ctx.fillStyle = 'rgba(255,138,101,0.9)';
      ctx.fillText('Arrivals',   labelX, trendPixelY(chart, fm.arrivalReg,   n - 1));
      ctx.fillStyle = 'rgba(128,203,196,0.9)';
      ctx.fillText('Departures', labelX, trendPixelY(chart, fm.departureReg, n - 1));
      ctx.restore();
    }

    function bgLabel(ctx, text, cx, cy) {
      ctx.save();
      ctx.font = '11px sans-serif';
      const w = ctx.measureText(text).width;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(cx - w / 2 - 3, cy - 9, w + 6, 14);
      ctx.fillStyle = '#ffffff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(text, cx, cy - 2);
      ctx.restore();
    }

    function drawTriangle(chart, fm) {
      const ctx   = chart.ctx;
      const ca    = chart.chartArea;
      const ds    = chart.data.datasets;
      const n     = ds[0].data.length;
      const { arrivals, departures } = fm;

      // Locate cursor data index j
      const cursorMs = chart.scales.x.getValueForPixel(fm.mouseX);
      const dates    = ds[0].data.map(d => new Date(d.x).getTime());
      const j = dates.reduce((best, t, i) =>
        Math.abs(t - cursorMs) < Math.abs(dates[best] - cursorMs) ? i : best, 0);

      const wip = arrivals[j] - departures[j];
      if (wip === 0) return;

      // Find j_c: first index > j where departures[k] >= arrivals[j] (fixed threshold)
      const threshold = arrivals[j];
      let j_c = -1;
      for (let k = j + 1; k < n; k++) {
        if (departures[k] >= threshold) { j_c = k; break; }
      }

      const xA = chart.scales.x.getPixelForValue(dates[j]);
      const yA = chart.scales.y.getPixelForValue(arrivals[j]);
      const yB = chart.scales.y.getPixelForValue(departures[j]);
      const xC = j_c >= 0 ? chart.scales.x.getPixelForValue(dates[j_c]) : null;

      ctx.save();
      ctx.beginPath();
      ctx.rect(ca.left, ca.top, ca.width, ca.height);
      ctx.clip();

      // Triangle fill (only when C is within range)
      if (xC !== null) {
        ctx.beginPath();
        ctx.moveTo(xA, yA);
        ctx.lineTo(xA, yB);
        ctx.lineTo(xC, yA);
        ctx.closePath();
        ctx.fillStyle = 'rgba(255,255,255,0.06)';
        ctx.fill();
      }

      // AB: vertical (WIP)
      ctx.setLineDash([]);
      ctx.lineWidth = 2;
      ctx.strokeStyle = '#ffffff';
      ctx.beginPath();
      ctx.moveTo(xA, yA);
      ctx.lineTo(xA, yB);
      ctx.stroke();

      if (xC !== null) {
        // AC: horizontal (cycle time)
        ctx.beginPath();
        ctx.moveTo(xA, yA);
        ctx.lineTo(xC, yA);
        ctx.stroke();
        // BC: dashed hypotenuse (throughput)
        ctx.setLineDash([4, 2]);
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(xA, yB);
        ctx.lineTo(xC, yA);
        ctx.stroke();
      } else {
        // C outside range: dashed extension to right edge
        ctx.setLineDash([4, 2]);
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(xA, yA);
        ctx.lineTo(ca.right, yA);
        ctx.stroke();
      }

      ctx.restore();

      // Labels
      const abMidY = (yA + yB) / 2;
      // WIP: right-aligned, left of AB
      ctx.save();
      ctx.font = '11px sans-serif';
      const wipText = 'WIP: ' + wip;
      const wipW = ctx.measureText(wipText).width;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(xA - wipW - 10, abMidY - 9, wipW + 6, 14);
      ctx.fillStyle = '#ffffff';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      ctx.fillText(wipText, xA - 5, abMidY - 2);
      ctx.restore();

      if (xC !== null) {
        const cycleTime = j_c - j;
        const throughput = (wip / cycleTime).toFixed(2);
        bgLabel(ctx, '~' + cycleTime + ' days', (xA + xC) / 2, yA - 10);
        bgLabel(ctx, throughput + '/day',        (xA + xC) / 2, (yA + yB) / 2 + 12);
      }
    }

    return {
      id: 'cfdFlowMetrics',

      afterInit(chart) {
        const { arrivals, departures } = buildArrays(chart);
        chart._flowMetrics = {
          mouseX:      null,
          arrivals,
          departures,
          arrivalReg:  linearRegression(arrivals),
          departureReg: linearRegression(departures)
        };
      },

      afterEvent(chart, args) {
        const fm = chart._flowMetrics;
        const ca = chart.chartArea;
        const { type, x, y } = args.event;
        if (type === 'mousemove' &&
            x >= ca.left && x <= ca.right &&
            y >= ca.top  && y <= ca.bottom) {
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
  })();
<% end %>
```

- [ ] **Step 2: Add the plugin to the Chart.js `plugins` array**

In the same file, find:

```javascript
    plugins: [cfdHatchPlugin],
```

Replace with:

```javascript
    plugins: [cfdHatchPlugin<% if @show_flow_metrics %>, cfdFlowMetricsPlugin<% end %>],
```

- [ ] **Step 3: Run the tests and verify all pass**

```bash
rake spec
```

Expected: all tests pass, including both new `show_flow_metrics` tests.

- [ ] **Step 4: Run RuboCop**

```bash
rubocop lib/jirametrics/cumulative_flow_diagram.rb lib/jirametrics/html/cumulative_flow_diagram.erb spec/cumulative_flow_diagram_spec.rb
```

Fix any offenses. Ignore the pre-existing `plugins:` warning in `.rubocop.yml`.
