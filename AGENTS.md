# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

JiraMetrics is a Ruby gem that extracts metrics from Jira and exports them as HTML reports and CSV files. It provides cycle time, throughput, aging, and other flow metrics visualizations. Documentation: https://jirametrics.org

## Build & Test Commands

```bash
rake                    # Run all tests (Jest + RSpec)
rake spec               # Run RSpec tests only
rake test_js            # Run Jest tests only
rake focus              # Run RSpec tests tagged with :focus

# Single test file
rspec spec/cycletime_scatterplot_spec.rb

# Single test by line number
rspec spec/cycletime_scatterplot_spec.rb:42

# JavaScript tests
npm test                # Run Jest tests
npm run test:watch      # Watch mode

# Linting
rubocop

# Build gem
gem build jirametrics.gemspec
```

## Architecture

### Data Flow

Config file (Ruby DSL) → `Exporter.configure {}` → Download via `JiraGateway` (curl-based HTTP) → JSON saved to target_path → `ProjectConfig.load_data()` creates `Issue` objects → Chart classes render via ERB templates → HTML report output

### Key Classes

- **`JiraMetrics`** (`lib/jirametrics.rb`): Thor CLI entry point with `download`, `export`, `go`, `info` commands
- **`Exporter`**: Singleton (`Exporter.configure {}` / `Exporter.instance`) that orchestrates projects. Uses `instance_eval` for DSL configuration
- **`ProjectConfig`**: Configuration and execution for a single project; loads JSON data, runs charts
- **`Issue`** (`lib/jirametrics/issue.rb`): Core domain model (~850 lines). Tracks changelog, cycle time, status transitions
- **`Board`**: Jira board configuration; maps statuses to columns, handles Kanban vs Scrum differences
- **`ChartBase`** (`lib/jirametrics/chart_base.rb`): Abstract base for all charts. Subclasses override `run` and call `wrap_and_render(binding, __FILE__)` which pairs with a matching `.erb` template
- **`Downloader`**: Factory pattern — `Downloader.create` returns `DownloaderForCloud` or `DownloaderForDataCenter`
- **`FileSystem`**: I/O abstraction injected into classes that do file operations (enables test mocking)

### Configuration DSL

The project uses a heavy block-based DSL pattern throughout. Config files are Ruby scripts using `instance_eval`:

```ruby
Exporter.configure do
  target_path 'output'
  project name: 'MyProject' do
    download do ... end
    html_report do
      cycletime_scatterplot
      aging_work_table
    end
  end
end
```

Helper methods `standard_project` and `aggregated_project` in `lib/jirametrics/examples/` provide reusable config patterns.

### Chart Templates

Each chart class in `lib/jirametrics/` has a matching ERB template in `lib/jirametrics/html/`. For example, `cycletime_scatterplot.rb` pairs with `html/cycletime_scatterplot.erb`. The JavaScript in `lib/jirametrics/html/index.js` handles foldable sections in the HTML output.

## Testing Patterns

### Test Helpers (spec/spec_helper.rb)

- `sample_board` / `load_complete_sample_board` — create Board from fixture data
- `load_issue(key, board:)` — load Issue from `spec/testdata/{key}.json`
- `empty_issue(created:, board:, key:)` — create minimal Issue for testing
- `mock_change(field:, value:, time:, value_id:, ...)` / `add_mock_change(issue:, ...)` — create/add ChangeItem entries
- `default_cycletime_config` — standard cycle time config using creation→last_resolution
- `to_time(string)` / `to_date(string)` — parse time strings (defaults to UTC for test consistency)
- `chart_format(object)` — format values for chart assertion comparisons

### Important Testing Notes

- Status names are not unique in Jira; `mock_change` with `field: 'status'` requires both `value` and `value_id`
- Test fixtures live in `spec/testdata/` (simple) and `spec/complete_sample/` (complex realistic data)
- SimpleCov with branch coverage is enabled; output goes to `coverage/`
- `load_settings` turns off `cache_cycletime_calculations` by default for tests

## Testing Requirements

Tests must always be written for new or modified functionality. There are no exceptions to this rule.

## Known Gotchas

### Timezone consistency
All timestamps must be in `exporter.timezone_offset` (default `+00:00`). Issue timestamps are converted on load via `Issue#parse_time`. Use `today_in_project_timezone` (`Time.now.getlocal(timezone_offset).to_date`) in downloaders — never `Date.today`, which uses the system local timezone and will cause issues to fall outside the date range.

### Chart.js time axis max
Chart.js interprets `max` as the *start* of that day, so always use `date_range.end + 1` for the max value on time-scale x-axes.

### chartjs-plugin-annotation v3 label position
The `position` property on a line annotation label accepts `'start'`, `'center'`, `'end'`, or a **percentage string** like `'25%'`. Decimal numbers (e.g. `0.25`) are silently ignored — the label stays at the default position with no warning or error. Always call `.to_json` when interpolating string values into JS heredocs.

### Running tests
Always run `rake spec` rather than individual spec files — running a single file causes `NameError: uninitialized constant MockFileSystem` due to a load-order dependency.

## Linting

After making changes to Ruby files, run `rubocop` on the modified files and fix any offenses before finishing. RuboCop warnings about `plugins:` vs `require:` in `.rubocop.yml` are pre-existing and can be ignored — only fix actual code offenses.

## Colours

### Colour-blind accessibility
All chart colours must be chosen from the **Okabe-Ito palette**, which is safe for all common forms of colour blindness (deuteranopia, protanopia, tritanopia):

| Name | Hex |
|---|---|
| Blue | `#0072B2` |
| Sky blue | `#56B4E9` |
| Bluish green | `#009E73` |
| Vermilion | `#D55E00` |
| Orange | `#E69F00` |
| Yellow | `#F0E442` |
| Reddish purple | `#CC79A7` |
| Black | `#000000` |

Blue and vermilion/orange are safe pairings because they differ in brightness as well as hue. Avoid red/green pairings.

### CSS variables and light/dark mode
All chart colours must be defined as CSS variables in `lib/jirametrics/html/index.css`. Every variable must appear in **four** places:
1. `:root` — light mode defaults
2. `html[data-theme="dark"]` — forced dark mode
3. `html[data-theme="light"]` — forced light mode
4. `@media screen and (prefers-color-scheme: dark) :root` — system dark mode

In ERB templates, reference colours via `CssVariable['--my-variable'].to_json`, which emits a `getComputedStyle(...)` call resolved at browser runtime so dark/light switching works live. Typically use lighter Okabe-Ito variants (e.g. sky blue `#56B4E9`) for dark mode and darker variants (e.g. blue `#0072B2`) for light mode to maintain contrast.

## Code Conventions

- Any DSL method that accepts a colour must also support a `[light_color, dark_color]` two-element array for light/dark mode. Use the private `parse_theme_color` helper in `CumulativeFlowDiagram` as the reference implementation (converts the pair to a `RawJavascript` theme-detection ternary). The same pattern is also in `GroupingRules#color=`.
- If a trailing `unless` modifier would require a line continuation (`\`) to wrap, use the multiline `unless/end` block form instead
- All Ruby files use `# frozen_string_literal: true`
- No method definition parentheses required (RuboCop `Style/MethodDefParentheses` disabled)
- Class variables are permitted (used for DSL patterns, e.g., `@@chart_counter` in ChartBase)
- Many RuboCop metrics (method length, ABC size, block length) are disabled — the DSL style produces long methods
- Use `FileSystem` for I/O in production code, not `File` directly
