# CFD Column Label and Label Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `label` and `label_hint` to `CfdColumnRules` so users can override band names in the legend and show tooltip text on legend hover.

**Architecture:** Two changes: (1) Ruby — add the attributes to `CfdColumnRules` and use them when building datasets in `run`; (2) ERB — add the Chart.js legend hover tooltip plugin (already present in `daily_wip_chart.erb`) to the CFD template.

**Tech Stack:** Ruby, RSpec, Chart.js (ERB template).

---

### Task 1: Add `label` and `label_hint` to `CfdColumnRules` and `run`

**Files:**
- Modify: `lib/jirametrics/cumulative_flow_diagram.rb`
- Test: `spec/cumulative_flow_diagram_spec.rb`

#### Background

`CfdColumnRules` currently has only `attr_accessor :color`. The `run` method builds datasets with `label: name` where `name` comes from `cfd[:columns]` (the board column name string). Datasets are iterated via `columns.each_with_index` where `col_index` is the position within the active (non-ignored) column list — the same index into `active_rules`.

The `chart_with_rules` helper already exists in the spec's `context 'column_rules'` block. Use it for the new tests.

- [ ] **Step 1: Write the failing tests**

Add inside the existing `context 'column_rules'` block in `spec/cumulative_flow_diagram_spec.rb` (after the three existing tests):

```ruby
it 'uses the custom label in place of the column name' do
  output = chart_with_rules {
    column_rules do |column, rule|
      rule.label = 'WIP' if column.name == 'In Progress'
    end
  }.run
  expect(output).to include('"label":"WIP"')
  expect(output).not_to include('"label":"In Progress"')
end

it 'includes label_hint in the dataset JSON when set' do
  output = chart_with_rules {
    column_rules do |column, rule|
      rule.label_hint = 'Items actively being worked on' if column.name == 'In Progress'
    end
  }.run
  expect(output).to include('Items actively being worked on')
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
rake spec
```

Expected: 2 failures — `label` and `label_hint` methods not defined on `CfdColumnRules`.

- [ ] **Step 3: Add `attr_accessor :label, :label_hint` to `CfdColumnRules`**

In `lib/jirametrics/cumulative_flow_diagram.rb`, change the `CfdColumnRules` class from:

```ruby
class CfdColumnRules < Rules
  attr_accessor :color
end
```

to:

```ruby
class CfdColumnRules < Rules
  attr_accessor :color, :label, :label_hint
end
```

- [ ] **Step 4: Use `label` and `label_hint` when building datasets in `run`**

In the `data_sets` mapping inside `run` (around line 116), change:

```ruby
{
  label: name,
  data: date_range.map { |date| { x: date.to_s, y: daily_marginals[date][col_index] } },
  backgroundColor: fill_colors[col_index],
  borderColor: border_colors[col_index],
  fill: true,
  tension: 0,
  segment: Segment.new(col_windows)
}
```

to:

```ruby
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
```

Note: `col_index` here is the position within `columns` (the filtered active list), which is the same index into `active_rules`. `label_hint: nil` is harmless — Chart.js ignores it, and the legend hover plugin guards with `if (!dataset?.label_hint)`.

- [ ] **Step 5: Run the tests and verify they pass**

```bash
rake spec
```

Expected: all tests pass including the 2 new ones.

- [ ] **Step 6: Run RuboCop**

```bash
rubocop lib/jirametrics/cumulative_flow_diagram.rb spec/cumulative_flow_diagram_spec.rb
```

Fix any offenses (ignore pre-existing `plugins:` warning in `.rubocop.yml`).

---

### Task 2: Add legend hover tooltip plugin to the ERB template

**Files:**
- Modify: `lib/jirametrics/html/cumulative_flow_diagram.erb`
- Test: `spec/cumulative_flow_diagram_spec.rb`

#### Background

`daily_wip_chart.erb` already has the legend hover tooltip mechanism. It works by:
1. Registering a custom `Chart.Tooltip.positioners.legendItem` (guarded so it's only registered once across multiple charts on the same page).
2. Setting `plugins.tooltip.position: 'legendItem'` with callbacks that show `dataset.label_hint` when the legend is being hovered.
3. Adding `plugins.legend.onHover` / `onLeave` handlers that set `chart._legendHoverIndex` and trigger the tooltip.

The positioner registration must be **outside** the IIFE (`(function() { ... })()`) so it runs at script-load time and is shared across charts. Everything else stays inside the IIFE.

The CFD's datasets are stored in reversed order (rightmost column = index 0). The hover callbacks use `legendItem.datasetIndex` from Chart.js directly, so reversal requires no special handling.

- [ ] **Step 1: Write a failing test**

Add inside the existing `context 'column_rules'` block in `spec/cumulative_flow_diagram_spec.rb`:

```ruby
it 'includes the legend hover tooltip plugin when label_hint is used' do
  output = chart_with_rules {
    column_rules do |column, rule|
      rule.label_hint = 'Some hint' if column.name == 'In Progress'
    end
  }.run
  expect(output).to include('onHover')
  expect(output).to include('legendItem')
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
rake spec
```

Expected: 1 failure — `onHover` not found in output.

- [ ] **Step 3: Update `cumulative_flow_diagram.erb`**

Replace the entire file with the following. The only changes from the current version are:
- Add the positioner guard block before the IIFE
- Add `tooltip:` plugin config inside `plugins:`
- Add `onHover:` and `onLeave:` to the `legend:` config

```erb
<%= seam_start %>
<div class="chart">
  <canvas id="<%= chart_id %>" width="<%= canvas_width %>" height="<%= canvas_height %>"></canvas>
</div>
<script>
if (!Chart.Tooltip.positioners.legendItem) {
  Chart.Tooltip.positioners.legendItem = function(items) {
    return this.chart._legendHoverPosition || Chart.Tooltip.positioners.average.call(this, items);
  };
}
(function() {
  const hatchWindows = <%= hatch_windows.to_json %>;

  // Custom plugin: draws diagonal hatching over correction windows in the affected band.
  // Uses createDiagonalPattern() defined in index.js.
  const cfdHatchPlugin = {
    id: 'cfdHatch',
    afterDraw: function(chart) {
      const ctx = chart.ctx;
      const ca  = chart.chartArea;
      hatchWindows.forEach(function(win) {
        const meta = chart.getDatasetMeta(win.dataset_index);
        if (!meta || !meta.data.length) return;

        const startX = chart.scales.x.getPixelForValue(new Date(win.start_date).getTime());
        const endX   = chart.scales.x.getPixelForValue(new Date(win.end_date).getTime());

        // Draw hatched slices over the correction window.
        // For stacked line charts, PointElement has no .base — derive the band bottom from the
        // dataset directly below in the visual stack (dataset_index - 1, since datasets are
        // stored reversed), or chart.chartArea.bottom for the lowest dataset.
        // Use a trapezoid clip path per slice so hatching stays within the actual band boundary
        // even when band height changes between data points.
        const belowMeta = win.dataset_index > 0 ? chart.getDatasetMeta(win.dataset_index - 1) : null;
        meta.data.forEach(function(point, i) {
          if (point.x < startX || point.x > endX) return;
          const prev       = i > 0 ? meta.data[i - 1] : null;
          const sliceLeft  = Math.max(prev ? prev.x : startX, startX);
          const sliceRight = Math.min(point.x, endX);
          if (sliceLeft >= sliceRight) return;

          const topLeft    = prev ? prev.y : point.y;
          const topRight   = point.y;
          const bottomLeft = belowMeta && prev && belowMeta.data[i - 1]
            ? belowMeta.data[i - 1].y : chart.chartArea.bottom;
          const bottomRight = belowMeta && belowMeta.data[i]
            ? belowMeta.data[i].y : chart.chartArea.bottom;

          if (Math.min(topLeft, topRight) >= Math.max(bottomLeft, bottomRight)) return;

          ctx.save();
          ctx.beginPath();
          ctx.rect(ca.left, ca.top, ca.width, ca.height);
          ctx.clip();
          ctx.beginPath();
          ctx.moveTo(sliceLeft,  topLeft);
          ctx.lineTo(sliceRight, topRight);
          ctx.lineTo(sliceRight, bottomRight);
          ctx.lineTo(sliceLeft,  bottomLeft);
          ctx.closePath();
          ctx.clip();
          ctx.fillStyle = createDiagonalPattern(win.color);
          ctx.fillRect(sliceLeft, Math.min(topLeft, topRight),
            sliceRight - sliceLeft, Math.max(bottomLeft, bottomRight) - Math.min(topLeft, topRight));
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
      elements: {
        point: { radius: 0 }
      },
      plugins: {
        tooltip: {
          position: 'legendItem',
          callbacks: {
            title: function(contexts) {
              if (contexts[0]?.chart._legendHoverIndex != null) return '';
            },
            label: function(context) {
              if (context.chart._legendHoverIndex != null) {
                return context.dataset.label_hint || '';
              }
            }
          }
        },
        legend: {
          reverse: true,
          onHover: function(event, legendItem, legend) {
            const chart = legend.chart;
            const dataset = chart.data.datasets[legendItem.datasetIndex];
            if (!dataset?.label_hint) return;
            chart._legendHoverIndex = legendItem.datasetIndex;
            chart._legendHoverPosition = { x: event.x, y: event.y };
            const firstNonZero = dataset.data.findIndex(d => d?.y !== 0);
            if (firstNonZero === -1) return;
            chart.tooltip.setActiveElements(
              [{ datasetIndex: legendItem.datasetIndex, index: firstNonZero }],
              { x: event.x, y: event.y }
            );
            chart.update();
          },
          onLeave: function(event, legendItem, legend) {
            legend.chart._legendHoverIndex = null;
            legend.chart._legendHoverPosition = null;
            legend.chart.tooltip.setActiveElements([], { x: 0, y: 0 });
            legend.chart.update();
          }
        }
      }
    }
  });
})();
</script>
<%= seam_end %>
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
rake spec
```

Expected: all tests pass including the new legend hover test.
