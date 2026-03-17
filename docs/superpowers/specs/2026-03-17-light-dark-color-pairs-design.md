# Light/Dark Mode Color Pairs for Grouping Rules

**Date:** 2026-03-17

## Problem

Grouping rules allow users to specify a single color per group. Charts are displayed in both light and dark modes, but a single color often looks wrong in one of the two modes. Users need a way to specify different colors for light and dark mode.

## Solution

Accept a two-element `[light_color, dark_color]` array wherever a grouping rule color is currently accepted. When an array is given, a deterministic CSS variable name is generated from the pair's content (via a short hash), the pair is stored on the `GroupingRules` object, the chart accumulates pairs into `generated_colors`, and `HtmlReportConfig` emits a `<style>` block appended to the CSS loaded for the report — placing it in `<head>` alongside existing styles.

## User-Facing API

```ruby
html_report do
  cycletime_scatterplot do
    grouping_rules do |issue, rules|
      rules.color = ['#4bc14b', '#2a7a2a']  # [light_color, dark_color]
    end
  end
end
```

Single-color usage (`rules.color = '#4bc14b'` or `rules.color = '--type-story-color'`) is unchanged. Each element of the array may be any valid CSS color value (hex, named color, etc.) — CSS variable references (`--foo`) are not allowed as array elements. If one is provided, `color=` raises `ArgumentError` with the message: `"CSS variable references are not supported as color pair elements; use a literal color value instead"`.

## Architecture

### `GroupingRules`

`color=` is extended to detect a two-element array:

- Generates a deterministic CSS variable name: `--generated-color-#{short_hash}`, where `short_hash` is the first 8 hex characters of the SHA256 of `"#{light}|#{dark}"`. The same pair always produces the same variable name — across charts, across runs.
- Sets `@color = CssVariable['--generated-color-#{short_hash}']` as today
- Stores `@color_pair = { light: light_color, dark: dark_color }` for later CSS emission

No callbacks or counter injection are required. `GroupingRules` is self-contained.

**Validation:** `color=` raises `ArgumentError` if an array is given that:
- does not have exactly two elements — message: `"Color pair must have exactly two elements: [light_color, dark_color]"`
- contains a non-string element — message: `"Color pair elements must be strings"`
- contains a string starting with `--` — message: `"CSS variable references are not supported as color pair elements; use a literal color value instead"`

Non-array values behave as today (passed through `CssVariable[]`).

**Equality:** Because variable names are derived deterministically from pair content, `eql?` (which compares `@color`) and `group` (which returns `[@label, @color]`) continue to work correctly — two rules with the same pair produce the same variable name and are considered equal.

### `ChartBase`

Adds a `generated_colors` accessor: a hash of `{ '--generated-color-XXXXXXXX' => { light: String, dark: String } }`, initialised to `{}`.

Charts that use grouping rules already collect `GroupingRules` objects during `run`. After evaluating the user block for each issue, the chart checks `rules.color_pair` and, if present, merges the entry into `@generated_colors`. No counter or external state is needed.

`@generated_colors` is reset to `{}` in `HtmlReportConfig#execute_chart` before calling `chart.run`, keeping the reset out of every subclass and consistent with how other per-run state (issues, time_range, etc.) is managed there.

### `HtmlReportConfig#execute_chart`

`@generated_colors` is initialised to `{}` in `HtmlReportConfig#initialize`, matching the existing pattern for `@sections` and `@charts`.

Before calling `chart.run`, resets `chart.generated_colors` to `{}`. After `chart.run`, merges `chart.generated_colors` into `@generated_colors`. Because variable names are content-addressed, merging identical pairs from multiple charts is idempotent.

### CSS Emission — `HtmlReportConfig#load_css`

`HtmlReportConfig` overrides `load_css(html_directory:)` (inherited from `HtmlGenerator`). The override calls `super(html_directory: html_directory)` to obtain the base CSS string (index.css plus any user `include_css`), then appends the generated block and returns the result. This ensures the generated variables are placed inside `<head>` alongside existing styles, which is the correct and standards-compliant location.

If `@generated_colors` is empty, nothing is appended.

The emitted block mirrors the three-selector pattern already used in `index.css`:

```css
:root {
  --generated-color-a1b2c3d4: #4bc14b;
}
@media (prefers-color-scheme: dark) {
  :root {
    --generated-color-a1b2c3d4: #2a7a2a;
  }
}
html[data-theme="dark"] {
  --generated-color-a1b2c3d4: #2a7a2a;
}
```

All three selectors must be emitted to correctly support both the system preference and the manual theme toggle button.

## Scope of Change

| Component | Change |
|-----------|--------|
| `GroupingRules` | Detect array in `color=`; generate deterministic variable name; store `@color_pair` |
| `ChartBase` | Add `generated_colors` accessor (initialised to `{}`) — populated by chart subclasses at their existing grouping-rule evaluation site |
| `HtmlReportConfig#initialize` | Add `@generated_colors = {}` |
| `HtmlReportConfig#execute_chart` | Reset `chart.generated_colors` before `chart.run`; merge into `@generated_colors` after |
| `HtmlReportConfig#load_css` | Override to append generated CSS block when `@generated_colors` is non-empty |

No changes to `CssVariable`, `HtmlGenerator#create_html`, `index.css`, `index.erb`, or any chart subclass.

## Testing

- **`GroupingRules`**
  - Array input produces a `CssVariable` color with the deterministic variable name
  - Same pair always produces the same variable name
  - `color_pair` accessor returns `{ light:, dark: }` for array input, `nil` for single-color input
  - `eql?` returns true for two rules with the same pair
  - Raises `ArgumentError` with appropriate message for arrays not containing exactly two elements
  - Raises `ArgumentError` with appropriate message for arrays containing non-string elements
  - Raises `ArgumentError` with appropriate message for arrays containing a `--`-prefixed string

- **`ChartBase`**
  - `generated_colors` returns `{}` when no color pairs are used
  - `generated_colors` is populated when a color pair is used in grouping rules

- **`HtmlReportConfig`**
  - `execute_chart` merges `chart.generated_colors` into `@generated_colors`
  - Merging the same pair from two charts is idempotent
  - `load_css` appends nothing when `@generated_colors` is empty
  - `load_css` appends a block containing all three selectors (`:root`, `@media (prefers-color-scheme: dark)`, `html[data-theme="dark"]`) with correct values when pairs are present
