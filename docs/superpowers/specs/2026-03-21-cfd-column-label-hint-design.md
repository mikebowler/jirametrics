# CFD Column Label and Label Hint Design

## Overview

Extend `CfdColumnRules` with `label` and `label_hint` attributes, following the same pattern as `GroupingRules`. `label` overrides the column name shown in the chart legend and dataset. `label_hint` renders as a tooltip when hovering the legend item, using the same mechanism already implemented in `DailyWIPChart`.

---

## Section 1: `CfdColumnRules` changes

Add two attributes to the `CfdColumnRules` inner class in `lib/jirametrics/cumulative_flow_diagram.rb`:

```ruby
attr_accessor :label, :label_hint
```

These mirror `GroupingRules#label` and `GroupingRules#label_hint` (see `lib/jirametrics/grouping_rules.rb`). No validation is required — both accept any string or nil.

---

## Section 2: `run` method changes

When building each dataset in `CumulativeFlowDiagram#run`, replace the bare column name with the rule's label if set, and include `label_hint`:

```ruby
{
  label: active_rules[col_index].label || name,
  label_hint: active_rules[col_index].label_hint,
  data: ...,
  ...
}
```

`label_hint: nil` is harmless — Chart.js ignores unknown dataset properties with nil/undefined values, and the legend hover plugin guards with `if (!dataset?.label_hint)`.

---

## Section 3: ERB template changes

Add the legend hover tooltip plugin to `lib/jirametrics/html/cumulative_flow_diagram.erb`, using the identical pattern from `lib/jirametrics/html/daily_wip_chart.erb`.

**Tooltip positioner** (registered once, guarded against double-registration):
```javascript
if (!Chart.Tooltip.positioners.legendItem) {
  Chart.Tooltip.positioners.legendItem = function(items) {
    return this.chart._legendHoverPosition || Chart.Tooltip.positioners.average.call(this, items);
  };
}
```

**`plugins.tooltip`** in the Chart.js config:
```javascript
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
}
```

**`plugins.legend`** — add `onHover` and `onLeave`:
```javascript
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
```

The dataset reversal (done = index 0) requires no special handling — `legendItem.datasetIndex` is the Chart.js array index, which is already correct.

---

## Section 4: Testing

In `spec/cumulative_flow_diagram_spec.rb`, add to the `context 'column_rules'` block:

- Custom `label` for a column overrides the column name in the output HTML (the original column name is absent as a dataset label, the custom label is present).
- `label_hint` set for a column appears in the output HTML.
