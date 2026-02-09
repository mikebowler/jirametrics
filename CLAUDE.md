# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Code Conventions

- All Ruby files use `# frozen_string_literal: true`
- No method definition parentheses required (RuboCop `Style/MethodDefParentheses` disabled)
- Class variables are permitted (used for DSL patterns, e.g., `@@chart_counter` in ChartBase)
- Many RuboCop metrics (method length, ABC size, block length) are disabled — the DSL style produces long methods
- Use `FileSystem` for I/O in production code, not `File` directly
