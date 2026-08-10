# Scatterplot Configurable Percentiles Design

## Overview

The scatterplot family hardcodes the 85th percentile in two places: the calculation
(`time_based_scatterplot.rb:124`, `percentile_value items, 85`) and the prose
(`cycletime_scatterplot.rb:18-23`, which writes "85%" three times plus a derived "15%").
This slice makes the percentile lines configurable, allows more than one, and allows none.

Scope is the scatterplot family only: `CycletimeScatterplot` and
`PullRequestCycleTimeScatterplot`, both of which inherit from `TimeBasedScatterplot`.
`FlowEfficiencyScatterplot` also inherits but opts out by clearing `@percentage_lines`
(`flow_efficiency_scatterplot.rb:57`) and is unaffected. Once we are happy with the result
here, the same pattern extends to the other charts tracked in bead jirametrics-4ad.

85 remains the default everywhere. An unchanged config must render byte-identical output.

## Section 1: Configuration DSL

One setter, `percentiles`, cascading over two levels.

```ruby
cycletime_scatterplot do
  percentiles [50, 85, 98]        # chart level

  grouping_rules do |issue, rule|
    rule.label = issue.type
    rule.color = color_for type: issue.type
    rule.percentiles = [85] if issue.type == 'Bug'   # this group only
  end
end
```

The chart-level value does double duty: it defines the overall (whole data set) lines AND
supplies the default for any group that does not set its own. `rule.percentiles` overrides
that default for one group.

`nil` means inherit; `[]` means explicitly none. `GroupingRules#percentiles` therefore must
NOT be initialised to `[]`, or "never set" becomes indistinguishable from "explicitly none".

Default is `[85]` at chart level, `nil` per group.

All four combinations are reachable:

| Want | Config |
|---|---|
| Overall on, groups on (today) | `percentiles [85]` |
| Both off | `percentiles []` |
| Overall off, groups on | `percentiles []` + `rule.percentiles = [85]` |
| Overall on, groups off | `percentiles [85]` + `rule.percentiles = []` |

Why one name rather than `percentiles` plus `overall_percentiles`: `percentiles` is already
the established setter on `time_based_histogram.rb:14` and `aging_work_in_progress_chart.rb:40`,
and 4ad names the histogram as the model the family should converge on. A second name would
split the vocabulary right as we are trying to unify it.

Why per-group config lives in `grouping_rules` rather than a hash keyed by group label:
group labels are computed at render time by an arbitrary user block
(`groupable_issue_chart.rb:19-43`) and can be issue type, sprint, assignee, or a date bucket.
They cannot be enumerated at config time, so a `'Bug' => [50, 85]` hash would string-match
something that does not exist yet, failing silently on a typo. Inside `grouping_rules` the
issue is in hand, so the decision is ordinary Ruby. This also mirrors how colour already
works: colour needs no per-percentile setting precisely because `rule.color` already owns it.

Note this setter is public API (config-block DSL), so the shape is a compatibility commitment.

## Section 2: Group identity

Group identity is defined by `GroupingRules#eql?`, which compares label and colour only.

`percentiles` must stay OUT of `eql?`. If it participated, two issues that differ only in
percentiles would split into two groups sharing a label and a colour, producing duplicate
legend entries.

Leaving it out means that if two issues in the same group somehow receive different non-nil
lists, whichever issue was seen first silently wins (Ruby `Hash` retains the original key
object). That can only be a config mistake, so detect it and raise, naming the group and both
lists, rather than letting it pass. The check belongs in `group_issues`.

A note for whoever fixes `Rules#hash` later, not a task for this slice. It currently returns
the constant `2` (`rules.rb:13-15`), which is a performance problem and nothing more:
everything collides into one bucket and `eql?` still decides correctly. The trap is that
identity is ALREADY defined in two places that must agree, `eql?` and `group` (which returns
`[@label, @color]` and is used for comparison at `daily_wip_chart.rb:84` and `:147`), and a
real `hash` would make three. All three must derive from the same fields, so the consistent
fix is `def hash = group.hash`. Whatever else happens, `percentiles` must stay out of all
three, or grouping breaks in a way that only shows up with per-group overrides set.

## Section 3: Calculation

`calculate_percent_line items` (single value, hardcoded 85) is replaced by a method returning
`[[percentile, value], ...]` for a given list, built on the existing
`percentile_value(items, n)` which already does the work and is already used by `compute_cap`.

`percentile_value` returns `nil` for an empty set, so entries with a `nil` value are dropped
before rendering rather than emitting an annotation at `yMin: null`.

`@percentage_lines` grows from `[value, color]` pairs to entries carrying percentile, value,
colour, and scope (`:overall` or the group). Scope is needed because the legend wiring in
Section 5 must map a dataset to exactly the lines belonging to that group.

Ordering: today `run` calls `create_datasets` first (pushing group lines), then appends the
overall line last (`time_based_scatterplot.rb:29-31`). The ERB relies on that ordering by
index. Section 5 removes that dependency, so ordering becomes free; keep groups first and
overall last purely so the diff on generated output stays small.

## Section 4: Rendering

Each entry becomes one Chart.js line annotation, as today, with three additions:

- `hitTolerance: 6`. The plugin computes its hit area as
  `(borderWidth + hitTolerance) / 2` (verified against the `v3.1.0` tag, not master).
  `hitTolerance` defaults to `0`, so with our `borderWidth: 1` the hit target is 0.5px and
  hovering is effectively impossible. 6 gives a ~3.5px band without changing appearance.
- A `label` with `display: false`, styled to match the existing `capLabel`
  (`time_based_scatterplot.erb:114-129`): `rgba(0,0,0,0.85)` background, white text, size 11.
- `enter`/`leave` callbacks flipping `label.options.display` and calling `chart.draw()`.

Content reads `"85% at 12 days"`, reusing `label_days` so pluralisation stays consistent.

The annotation plugin does not feed Chart.js's native tooltip, so this is the plugin's own
label and its styling is hand-matched rather than inherited. `capLabel` already does exactly
this, so we are following an existing pattern, not inventing one.

No dash-pattern or opacity encoding. Density is the user's choice; hover identification is
enough.

Legend text KEEPS its parenthetical, generalised to N values. An earlier draft dropped it in
favour of hover, which was wrong on two counts: it contradicts the byte-identical guarantee in
Section 8, and it moves always-visible information behind an interaction. Format:

- one percentile: `Story (85% at 81 days)`, character-for-character what ships today
- several: `Story (50% at 3 days, 85% at 12 days, 98% at 40 days)`
- none (group set to `[]`): `Story`, no parenthetical

Long labels are the user's problem to manage by asking for fewer lines, consistent with
density being their choice.

We are on `chartjs-plugin-annotation` 3.1.0 (`index.erb:9`), which is the current latest
release. No upgrade is needed or available.

## Section 5: Legend wiring (the risky part)

Today `erb:155` does:

```js
legend.chart.options.plugins.annotation.annotations["line"+(i/2)].display = nextVisibility;
```

This assumes datasets come in pairs (data, trendline) so `i/2` is the group index, and that
each group owns exactly one annotation. Both assumptions die when a group can own N lines.

Replace the arithmetic with an explicit map emitted from Ruby, dataset index to the list of
annotation ids for that group, and have the handler iterate that list. This removes the
existing fragility rather than extending it. The overall lines appear in no group's list, so
they stay visible when a group is toggled off, matching today's behaviour.

## Section 6: Prose

`cycletime_scatterplot.rb:18-23` is templated from the configured chart-level list. Cases:

- One percentile: the current sentence with the number and its complement injected
  (85 and 15 today), preserving the "reasonable proxy for most" framing.
- Several: name each with its value, and drop the singular "most work will complete in N days"
  framing, which only makes sense for one line.
- Empty: emit no paragraph about lines at all. It must not render a sentence describing lines
  that were deliberately switched off.

`PullRequestCycleTimeScatterplot` needs NO prose work. Its `description_text`
(`pull_request_cycle_time_scatterplot.rb:12-15`) never mentions the percentile lines at all,
even though it draws them. That is a pre-existing documentation gap, not something this slice
introduces, and templating prose that does not exist would be inventing scope. It still picks
up the configurable lines by inheritance.

The JS comments at `time_based_scatterplot.erb:154` and
`flow_efficiency_scatterplot.erb:60` say "the 85% line" and need rewording.

## Section 7: Edge cases

- Empty percentile list at both levels: no annotations, no prose paragraph, chart still renders.
- A percentile that yields `nil` (no values after filtering): drop that line silently.
- Percentile of 100 or 0: allowed, no special casing. `percentile_value` clamps the index with
  `[values.size * percentile / 100, values.size - 1].min`.
- Duplicate values in the list (e.g. `[85, 85]`): de-duplicate, or two identical annotations
  stack invisibly and the hover picks one arbitrarily.
- Validation: reject non-integer and out-of-range values at config time with a message naming
  the offending value, since a typo here silently produces a wrong chart.
- Interaction with `cap_y_axis`: unchanged. Percentile lines are computed from the full data
  set, never from capped display values. This invariant is stated in the cap design doc
  (2026-08-05) and there is a regression test for it; do not break it.

## Section 8: Testing

Follow the established pattern: stub `wrap_and_render` and assert the ivars `run` builds.

- Default config produces exactly one overall line at 85 and one line per group at 85, and the
  generated output is unchanged from today. This is the byte-identical guarantee.
- `percentiles []` produces no lines and no prose paragraph.
- Chart-level list of several produces the right count and values.
- `rule.percentiles` overrides for one group while others inherit.
- `rule.percentiles = []` silences one group while the overall line survives.
- `nil` versus `[]` distinction is exercised directly.
- Conflicting percentiles within one group raises, naming the group.
- A percentile yielding `nil` is dropped rather than rendered.
- Legend map: each dataset index maps to exactly its own group's annotation ids.
- Existing cap tests continue to pass unchanged.

## Section 9: User documentation

In `../jekyll_jirametrics`:

- Document `percentiles` on the scatterplot in `config_charts.md`, including the per-group
  override and the empty-list case. Note that `grep percentiles ../jekyll_jirametrics/*.md`
  currently returns nothing, so the setter is undocumented even on the charts that already
  support it. Documenting the scatterplot is the first instalment.
- `config_charts.md:142` says the percentile lines are "such as the 85% line" and should
  reference the setting instead.
- Add a `changes.md` entry, since this is behaviour-affecting configuration.

## Out of scope (deferred, not part of this slice)

- The other charts in bead jirametrics-4ad: the aging bar chart percent line, the board
  movement forecast, the WIP-by-column recommendation, and the aging WIP CSS variable
  fallback. Deliberately deferred until this slice proves the pattern.
- `random_color` consolidation and theming, tracked as jirametrics-yu8.
- The unpinned `chart.js` CDN reference at `index.erb:7`, which serves whatever is current at
  render time while the annotation plugin beside it is pinned. A real fragility, unrelated to
  this work, and worth its own bead.
- Explaining what the trend lines mean, tracked as jirametrics-kwz.
