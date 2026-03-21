# Cumulative Flow Diagram Design

## Overview

Add a `CumulativeFlowDiagram` chart to jirametrics that shows how work accumulates across board columns over time. Each band in the chart represents items that have reached that column or further, making it easy to spot bottlenecks, work-in-progress growth, and flow irregularities.

---

## Section 1: Architecture

Two classes with a clear separation of concerns:

- **`CfdDataBuilder`** (`lib/jirametrics/cfd_data_builder.rb`) — pure computation class. Accepts `board:`, `issues:`, and `date_range:` as keyword arguments (`date_range` is a `Date` range). No chart infrastructure, no rendering. Fully unit-testable in isolation.
- **`CumulativeFlowDiagram < ChartBase`** (`lib/jirametrics/cumulative_flow_diagram.rb`) — thin rendering class. In its `run` method, `require`s `cfd_data_builder`, instantiates `CfdDataBuilder` passing `current_board` (the inherited `ChartBase#current_board`), `issues`, and `date_range`. Passes results to an ERB template that renders a Chart.js stacked area chart.

Does NOT include `GroupableIssueChart`. Uses standard `ChartBase` block handling for `header_text`/`description_text` overrides.

The chart is auto-registered via the existing `method_missing` dispatcher (`cumulative_flow_diagram` → `CumulativeFlowDiagram`). No `define_chart` call is needed.

Template file: `lib/jirametrics/html/cumulative_flow_diagram.erb`

Default texts:
- `header_text`: `'Cumulative Flow Diagram'`
- `description_text`: `nil`

---

## Section 2: Computation (`CfdDataBuilder`)

### Input
- `board:` — Jira board; uses `board.visible_columns`, each with `status_ids` returning an array of integers (status IDs)
- `issues:` — all issues for the project
- `date_range:` — a `Date` range

### Algorithm

**Column mapping:** Build a hash from status ID (integer) → column index by iterating `board.visible_columns` and their `status_ids` arrays.

**High-water-mark per issue:** For each issue, track the furthest-right column index it has ever reached (starting at `nil` = "not yet on board"). Also track a `correction_open_since` date (starts `nil`). Process status changes via `issue.status_changes` in chronological order. `change.value_id` is already an integer for status changes (set as `@raw['to']&.to_i` in `ChangeItem`).

For each status change:

- Column lookup result is `nil` (status not on board): skip this change, leave high-water-mark unchanged.
- Resolved column index > current high-water-mark (or high-water-mark is `nil`): advance the high-water-mark. If `correction_open_since` is set, close the correction window (`end_date = change.time.to_date`) and clear `correction_open_since`.
- Resolved column index < current high-water-mark: backwards movement. If `correction_open_since` is `nil`, open a new correction window (set `correction_open_since = change.time.to_date`). If a correction window is already open (multiple backwards moves without recovery), do not open a new one — keep the existing window open and leave the high-water-mark unchanged.

After processing all changes: if `correction_open_since` is still set, close the correction window with `end_date = date_range.end`.

Each closed correction window records:
- `start_date`: when the first uncovered backwards move occurred
- `end_date`: date the issue re-advanced to or past the high-water-mark, or `date_range.end`
- `column_index`: the high-water-mark column at the time the window was opened (the column the issue was dropped from)

**Initial snapshot (pre-range issues):** Before iterating `date_range`, process all status changes that occurred *before* `date_range.begin` to establish each issue's high-water-mark at the start of the range. Issues with no status changes of any kind (never appeared on the board) contribute 0 to all columns.

**Daily counts — cumulative totals:** For each date in `date_range`, emit one count per column. The count for column `i` is the number of issues whose high-water-mark is `>= i`. These are cumulative totals stored in board left-to-right order:

```
[12, 8, 3, 1]   # 12 issues reached column 0+; 8 reached column 1+; 3 reached column 2+; 1 reached column 3
```

This is an O(days × issues) scan, acceptable for typical project sizes.

**Issue that skips columns:** An issue jumping from column 0 directly to column 3 (high-water-mark = 3) is counted in all of columns 0, 1, 2, and 3 because `3 >= 0, 1, 2, 3`. This falls naturally out of the cumulative-total semantics.

### Output
```ruby
{
  columns: ['Ready', 'In Progress', 'Review', 'Done'],  # visible column names, left-to-right order
  daily_counts: {
    Date.new(2024, 1, 1) => [12, 8, 3, 1],   # cumulative totals, left-to-right order
    Date.new(2024, 1, 2) => [13, 9, 3, 2],
    # ...
  },
  correction_windows: [
    {
      start_date: Date.new(2024, 1, 5),
      end_date: Date.new(2024, 1, 7),   # date of recovery, or date_range.end
      column_index: 2                   # the high-water-mark column when the window opened
    }
  ]
}
```

---

## Section 3: Rendering (`CumulativeFlowDiagram`)

### Chart type
Chart.js stacked line chart with `fill: true`. One dataset per visible column.

**Marginal conversion:** `daily_counts` holds cumulative totals. Chart.js stacks datasets additively, so the ERB template converts to marginal band heights. All values remain in left-to-right column order throughout this conversion:

```
marginal[i] = cumulative[i] - cumulative[i+1]   # for i < last column
marginal[last] = cumulative[last]
```

**Dataset order for Chart.js:** After conversion, pass datasets in *reverse* order (done column first = bottom of stack, leftmost column last = top of stack). This makes the largest band (leftmost) sit on top, producing the traditional CFD shape. The marginal conversion uses the original left-to-right order regardless of this reversal.

**Legend order:** Because datasets are reversed, Chart.js would render the legend in reverse order. Use `options.plugins.legend.reverse: true` to restore left-to-right legend display.

### Backwards movement visualization (both signals — dashed line + hatched fill)

**Dashed border line** — via Chart.js `segment` callback on `borderDash`. Each dataset carries a `correctionWindows` property (array of `{start_date, end_date}` for its column). The segment callback checks whether the segment's midpoint date falls within any correction window for that dataset.

**Hatched fill** — via a custom Chart.js `afterDraw` plugin registered inline in the ERB template. After the chart draws, the plugin iterates each correction window:

1. Map `start_date` and `end_date` to pixel x-coordinates via `chart.scales.x.getPixelForValue(date)`.
2. Find the dataset index for the affected column. Get top and bottom pixel y-coordinates for the band using Chart.js dataset meta: `chart.getDatasetMeta(datasetIndex).data[pointIndex].y` (top of band) and `chart.getDatasetMeta(datasetIndex).data[pointIndex].base` (bottom of band).
3. Draw over the region using `createDiagonalPattern(color)` (already defined in `index.js`) as the canvas `fillStyle`.

### X-axis max
Use `date_range.end + 1` as the x-axis `max`. Chart.js interprets `max` as the *start* of that day, which would otherwise cut off the last day.

### Axes and labels
- X-axis: time scale, one point per day, `max: date_range.end + 1`
- Y-axis: linear, starting at 0, label "Number of items"
- Legend: one entry per column, left-to-right order (use `legend.reverse: true`)

### Configuration DSL
```ruby
cumulative_flow_diagram do
  header_text 'Flow across board columns'
end
```

---

## Section 4: Testing

### `CfdDataBuilder` spec (`spec/cfd_data_builder_spec.rb`)
Pure unit tests — no chart infrastructure required. Uses `empty_issue`, `add_mock_change`, and `sample_board` from `spec_helper.rb`.

- **Happy path:** 3 issues with status changes spanning the date_range. Verify `daily_counts` has correct cumulative values per column per date.
- **Correction window — recovered:** Issue moves from column 2 back to column 1, then later re-advances to column 2. Verify `correction_windows` has one entry: `start_date` = date of backwards move, `end_date` = date of re-advance, `column_index` = 2.
- **Correction window — not recovered:** Same backwards move, issue never re-advances within the range. Verify `end_date` = `date_range.end`.
- **Multiple backwards moves without recovery:** Issue drops from column 2 to column 1, then from column 1 to column 0. Verify only one correction window is recorded (not two), with `start_date` = date of first backwards move.
- **Status not on board:** Status change whose `value_id` is not in any board column is skipped — high-water-mark unchanged.
- **Pre-range issues:** Issue with changes before `date_range.begin`. Verify it appears in the day-0 snapshot.
- **Never on board:** Issue with no status changes at all contributes 0 to all columns.
- **Issue skips columns:** Issue moves directly from column 0 to column 3. Verify columns 0, 1, 2, and 3 all gain a count.
- **Single-day range:** `date_range` of one day. Verify `daily_counts` has exactly one key.

### `CumulativeFlowDiagram` spec (`spec/cumulative_flow_diagram_spec.rb`)
Integration-level chart spec using `MockFileSystem` and `load_complete_sample_board`. Follows the pattern of existing chart specs.

- Chart renders without error.
- Output HTML contains the expected column names from the board.
- Output HTML contains `borderDash` (confirming the segment callback is present).
