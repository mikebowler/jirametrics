# Scatterplot Y-Axis Cap Design

## Overview

Outliers with very long cycletimes stretch the y-axis so far that the bulk of the
data is crushed into the bottom of the chart and becomes unreadable. Making the
chart taller does not help, because the problem is the range, not the height.

This feature lets a chart cap its y-axis at a chosen percentile of the data. Items
above the cap are not dropped and are not clipped: they are moved into a visually
distinct "gutter" band above an axis break, so the reader can still see that the
outliers exist, how many there are, and (on hover) their true values, while the
bulk of the data expands to fill the readable area below the break.

The feature is opt-in and off by default. Existing reports render exactly as they
do today unless capping is explicitly enabled. It ships for the time based
scatterplot family only (`CycletimeScatterplot` and
`PullRequestCycleTimeScatterplot`, both inheriting `TimeBasedScatterplot` and
sharing `time_based_scatterplot.erb`). Generalizing to other chart types is
deferred.

The UX was proven with an interactive Chart.js prototype and reviewed by the
client, who approved it.

---

## Section 1: Configuration DSL

A new config-block setter on `TimeBasedScatterplot`:

```ruby
cap_y_axis percentile: 98
```

- **Opt-in.** With no `cap_y_axis` call, behaviour is identical to today.
- **Percentile only for now.** The `percentile:` keyword is the only supported
  mode. A fixed-value mode (`cap_y_axis at: 45`) is intentionally NOT built yet;
  the noun-first name reserves room to add it later without a new verb.
- **Default when omitted.** `cap_y_axis` with no argument defaults to the 98th
  percentile. Capping is for the genuine long tail, so 98 keeps all but the
  extreme outliers on-scale.
- **Singular `percentile:` is deliberate.** It is distinct from the existing
  plural `percentiles [...]` setter (used by `TimeBasedHistogram` and
  `AgingWorkInProgressChart` for reference lines). The two coexist: `percentiles`
  configures analytical reference *lines*; `cap_y_axis percentile:` configures the
  *viewport*. They are different concepts and are kept lexically distinct.

The setter stores the configuration (for example `@y_axis_cap = { percentile: 98 }`,
or `nil` when disabled). Naming of the ivar is an implementation detail for the
plan.

---

## Section 2: The statistics invariant

Capping is a view concern only. It must not change any computed number.

- The overall and per-type 85% percentile lines
  (`TimeBasedScatterplot#calculate_percent_line`) continue to be computed from the
  full item set, exactly as today.
- Trend lines continue to be computed from the full data.
- The cap percentile itself is computed over the same set the percentile lines use,
  including the existing `minimum_y_value` filtering (values below the minimum are
  excluded before ranking, matching `calculate_percent_line`).

A green test that asserts the 85% line and trend values are unchanged when capping
is toggled is part of the acceptance criteria.

---

## Section 3: Vertical layout

Let `cutoff` be the value at the configured percentile. The y-axis is laid out as:

```
  axisMax  ┌───────────────────────────┐
           │      grey gutter band      │   <- up-arrows pinned here (one row)
           │   [ N items above X days ] │   <- count label, opaque background
  sep      ╞═══════════════════════════╡   <- double rule (the axis break)
           │        padding gap         │   <- keeps top real dot off the rule
  cutoff   ├───────────────────────────┤
           │                            │
           │     real data 0..cutoff    │   <- round dots at true cycletime
           │                            │
      0    └───────────────────────────┘
```

Layout constants, expressed relative to `cutoff` (matching the approved
prototype):

- `pad = cutoff * 0.06` (breathing room above the topmost real dot)
- `gutterH = cutoff * 0.15` (height of the arrow band above the break)
- `sep = cutoff + pad` (the break location)
- `axisMax = ceil(sep + gutterH)`
- `pinRow = sep + gutterH * 0.55` (the single row where outliers sit)

`cutoff`, `sep`, `axisMax`, `pinRow`, and the outlier count are computed in Ruby
and passed to the template.

---

## Section 4: Point handling (Ruby)

In `data_for_item` (or an equivalent seam), when capping is enabled and an item's
`y_value` exceeds `cutoff`:

- Emit the point with `y` set to `pinRow` instead of its true value.
- Preserve the true value on the point (for example `trueY`) so the tooltip can
  report it.
- Mark the point as over-cap (for example `over: true`) so the template can style
  it.

Points at or below `cutoff` are emitted unchanged. This keeps one dataset per type
(the legend is unchanged) and lets the template assign per-point styling from the
`over` flag.

`@highest_y_value` (used to size the axis and to bound trend lines) must be clamped
to `cutoff` when capping is on, so the auto-scaling and the trend line do not chase
an outlier off the top. The trend line's `max_y` becomes `cutoff` rather than the
raw highest value, so a projected trend does not shoot into the gutter.

---

## Section 5: Rendering (ERB template)

All cap-related rendering is emitted only when capping is enabled AND at least one
item is over the cap. With capping disabled, or with no outliers, the template
renders as it does today (no break, no gutter, no arrows).

1. **Y-axis bounds.** `max` becomes `axisMax`. A ticks callback suppresses any tick
   above `cutoff` so no axis numbers appear inside the break or gutter.

2. **Gutter band.** A `box` annotation from `sep` to `axisMax`, filled with a faint
   theme-aware wash (light: subtle dark; dark: subtle light).

3. **Double rule (the axis break).** Drawn by a small Chart.js plugin in
   `afterDatasetsDraw`, in pixel space: two `1.5px` lines `3px` apart at the pixel
   position of `sep`. Pixel space is required so the gap stays a hairline
   regardless of the axis scale (an earlier data-unit version ballooned the gap as
   the range grew). The rule colour reads from a theme CSS variable.

4. **Count label.** "N items above X days", anchored near the break with
   `yAdjust` lifting it into the gutter so the two rule lines do not cross the text,
   on an opaque background for legibility.

5. **Up-arrow markers.** Over-cap points render as an up-arrow glyph in the item's
   type colour. The glyph is drawn on a small canvas and used as the Chart.js
   `pointStyle`. In the template, after the datasets are serialized, build per-point
   `pointStyle` and `pointRadius` arrays from the `over` flag: `over` points get the
   arrow canvas (coloured from the dataset's colour) and a larger radius; all others
   get `circle`. This post-processing must skip the interleaved trend-line datasets
   (they are `type: 'line'`).

The up-arrow was chosen over a triangle because a triangle reads as just another
series marker; an arrow unambiguously means "the real value continues upward beyond
this point." This was confirmed in client review.

---

## Section 6: Theme (light and dark)

The chart must remain legible in both light and dark themes. The gutter wash, the
rule colour, the grid, and axis text all derive from theme CSS variables rather
than hardcoded colours, consistent with how the rest of the report themes itself
(for example `--grid-line-color`). The dark-mode gutter wash is the element most
likely to need tuning; verify it stays distinguishable from the plot background.

---

## Section 7: Edge cases

- **No outliers.** All data at or below `cutoff`: render as today, with no break,
  gutter, arrows, or count label.
- **Cap below a reference-line percentile.** If someone sets `cap_y_axis percentile:`
  below the percentile of a drawn reference line (for example capping at the 80th
  while an 85% line is shown), that line's value would fall in or above the gutter.
  This is an unusual misconfiguration. Acceptable behaviour for this slice is that
  the line is drawn at its true value and may land in the gutter region; document
  that the cap percentile should sit above any reference lines. No special handling
  is built.
- **Empty data set.** The existing "No data matched" short-circuit in
  `TimeBasedScatterplot#run` is unaffected.

---

## Section 8: Testing

- **Ruby, data assembly.** Following the project convention, exercise `#run` by
  stubbing `wrap_and_render` and asserting the assembled ivars and dataset
  structures: cap disabled by default; when enabled, over-cap points remapped to
  `pinRow` with the true value preserved and `over` set; `axisMax` and `cutoff`
  computed from the full (min-filtered) set; the default percentile is 98; a custom
  percentile is honoured; the no-outliers case produces no cap artifacts.
- **Statistics invariant.** Assert the 85% percentile line values and trend-line
  values are identical with capping on and off for the same data.
- **Characterization.** Existing scatterplot specs stay green unchanged (capping off
  by default).
- **Rendered output.** Verify the real HTML chart in a browser, in both light and
  dark themes, including hovering an arrow to confirm the true cycletime shows.
- **RuboCop clean** on all touched files.

---

## Section 9: User documentation

`cap_y_axis` is public, user-facing DSL, so shipping it includes updating the
separate Jekyll docs repo at `../jekyll_jirametrics` (published to
jirametrics.org):

- Document the `cap_y_axis percentile:` setter in the scatterplot / chart
  configuration reference, including the default (98), that it is opt-in, and how
  the outlier gutter reads.
- Add a `changes.md` changelog entry for the new behaviour.

Docs are deployed separately via `rake deploy` from that repo; deployment timing is
the author's call and is not part of the code change itself.

---

## Out of scope (deferred, not part of this slice)

- Other chart types. We evaluated generalizing the cap across the chart catalogue
  (post-ship, 2026-08-05) and concluded it stays a scatterplot-family tool. The cap
  earns its place only when all three hold: (a) the value axis is a continuous,
  unbounded quantity; (b) a few rare extreme values compress the meaningful bulk;
  and (c) those outliers are noise you read past, not the primary signal. That fits
  the cycletime and PR cycletime scatterplots, and nothing else in the catalogue:
    - Histogram: the distribution is the subject and the tail is information, not
      noise (fails a and c); binning already tames the range.
    - daily_wip / throughput / WIP-by-column / CFD: the axis is counts or a
      cumulative total, every value is load-bearing and comparable, and you need
      the full range, so nothing can be pushed off-scale (fails a and c).
    - flow efficiency: a bounded percentage (0-100), nothing to compress.
    - Aging work (bar): the age axis genuinely gets compressed by one ancient
      stuck item (a and b hold), but that oldest item is usually the most important
      thing on the chart, so pinning it into a gutter would bury the signal the
      chart exists to surface (fails c). This is the interesting near-miss.
  So there is no seam to extract until a chart appears with the "outliers are noise,
  not signal" property. None does today.
- The fixed-value mode `cap_y_axis at: 45`. Reserved by the naming; not built.
- Making the scatterplot family's hardcoded 85% line configurable and
  de-hardcoding its prose to adopt the existing `percentiles` setter. This is a
  separate, larger slice (it touches the calculation, the per-type line
  multiplication, and the text in `cycletime_scatterplot.rb`).
- Explaining what the trend lines mean in the description text (tracked separately
  as bead jirametrics-kwz).
