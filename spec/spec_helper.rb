# frozen_string_literal: true

# RSpec.configure do |config|
#   config.formatter = :html
# end

ENV['RACK_ENV'] = 'test'

# simplecov depends on date_core, a C extension that JRuby cannot load.
# Skip it in subprocess spec runs (see the leaked-SystemExit regression test) so the
# child process doesn't restart coverage and pollute its output.
# The $PROGRAM_NAME guard keeps coverage to genuine rspec runs: mutant and other runners
# load this helper too, but boot under a non-rspec $0 - starting SimpleCov there just writes
# a junk "Unknown Test Framework" result that later trips SimpleCov's stale-merge warning.
if RUBY_ENGINE == 'ruby' && !ENV['JIRAMETRICS_SUBPROCESS_SPEC'] && $PROGRAM_NAME.end_with?('rspec')
  require 'simplecov'
  SimpleCov.start do
    enable_coverage :branch
    skip '/spec/'
    SimpleCov.skip do |src_file|
      File.basename(src_file.filename) == 'config.rb'
    end
  end
end

require 'require_all'
require_all 'lib'

# Auto-load shared test support classes (mocks, matchers, builders) from spec/support.
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  # Run examples in a random order and seed the global RNG from the same seed so runs
  # are reproducible with --seed. Random ordering surfaces order-dependent test pollution.
  config.order = :random
  Kernel.srand config.seed

  # Guard against a production exit()/abort() call leaking out of an example. RSpec doesn't
  # rescue SystemExit, so a leaked exit terminates the whole run early with a misleading
  # partial "0 failures" summary. Convert it into a normal, localized failure so the suite
  # keeps running and names the culprit. Tests that intentionally exercise an exit path still
  # pass - their `expect { ... }.to raise_error(SystemExit)` rescues the exit before this hook.
  config.around do |example|
    example.run
  rescue SystemExit => e
    raise "Example leaked a SystemExit (exit status #{e.status}). A production " \
          'exit()/abort() call escaped the example and would otherwise terminate the whole ' \
          'suite early. Wrap the code under test in `expect { ... }.to raise_error(SystemExit)`, ' \
          'or stop it reaching the exit.'
  end
end

# Fixture builders for this repo's own specs. Free to change without ceremony: nothing outside
# this repository can see them. The public equivalent, which extension authors can rely on and
# which therefore cannot change freely, is JiraMetrics::Testing in lib/jirametrics/testing.rb.
module SpecHelpers
  # Also available as SpecHelpers.something, for the support classes in spec/support and for blocks
  # that get instance_eval'd against something else. Those cannot rely on the include below.

  module_function

  def file_read filename
    File.read filename, encoding: 'UTF-8'
  end

  def sample_board
    MockBoard.load(
      statuses: './spec/testdata/sample_statuses.json',
      configuration: './spec/testdata/sample_board_1_configuration.json'
    )
  end

  # A board whose statuses are replaced with a fixed, known set (ids 1-15) so blocked/stalled tests
  # can reference them by name (in the blocked_statuses/stalled_statuses settings) and by id (in
  # add_change value_ids). Pass a project_config when the surrounding spec needs to share it;
  # otherwise a MockFileSystem-backed one is built.
  # A flat block of fixture setup; splitting it into helpers wouldn't make the test data any clearer.
  def board_with_blocked_stalled_statuses project_config: nil # rubocop:disable Metrics/MethodLength
    board = sample_board
    board.project_config = project_config || ProjectConfig.new(
      exporter: Exporter.new(file_system: MockFileSystem.new), target_path: 'spec/testdata/',
      jira_config: nil, block: nil
    )
    statuses = board.possible_statuses
    statuses.clear

    # Ordinary flow statuses.
    statuses << Status.new(
      name: 'Backlog', id: 1, category_name: 'ready', category_id: 2, category_key: 'new'
    )
    statuses << Status.new(
      name: 'Selected for Development', id: 3, category_name: 'ready', category_id: 4, category_key: 'new'
    )
    statuses << Status.new(
      name: 'In Progress', id: 5, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Review', id: 7, category_name: 'in-flight', category_id: 8, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Done', id: 9, category_name: 'finished', category_id: 10, category_key: 'indeterminate'
    )

    # Blocked/stalled fixtures referenced by the blocked_statuses/stalled_statuses settings.
    statuses << Status.new(
      name: 'Blocked', id: 10, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Stalled', id: 11, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Doing', id: 12, category_name: 'finished', category_id: 10, category_key: 'done'
    )
    statuses << Status.new(
      name: 'Doing2', id: 13, category_name: 'finished', category_id: 10, category_key: 'done'
    )
    statuses << Status.new(
      name: 'Stalled2', id: 14, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    statuses << Status.new(
      name: 'Blocked2', id: 15, category_name: 'in-flight', category_id: 6, category_key: 'indeterminate'
    )
    board
  end

  def load_issue key, board: nil
    board = sample_board if board.nil?
    issue = MockIssue.new(raw: JSON.parse(file_read("spec/testdata/#{key}.json")), board: board)
    issue.raw['exporter'] = 1 # Make it look like this issue was actually loaded from Jira. Ie not artificial.
    issue
  end

  def load_complete_sample_issues board:
    result = []
    Dir.each_child './spec/complete_sample/sample_issues' do |file|
      next unless file.match?(/SP-.+/)

      result << Issue.new(raw: JSON.parse(file_read("./spec/complete_sample/sample_issues/#{file}")), board: board)
    end

    # Sort them back into the order they would have come from Jira because some of the tests are order dependant.
    result.sort_by(&:key_as_i).reverse
  end

  def load_complete_sample_board
    MockBoard.load(
      statuses: './spec/complete_sample/sample_statuses.json',
      configuration: './spec/complete_sample/sample_board_1_configuration.json'
    )
  end

  def load_complete_sample_statuses
    load_statuses './spec/complete_sample/sample_statuses.json'
  end

  def status_collection_for board:, names:
    collection = StatusCollection.new
    names.each do |name|
      board.possible_statuses.find_all_by_name(name).each { |s| collection << s }
    end
    collection
  end

  def load_statuses input_file
    MockBoard.load_statuses input_file
  end

  # If either value or old_value are statuses then the name and id will be pulled from that object
  def load_settings
    JSON.parse(File.read('./lib/jirametrics/settings.json')).tap do |settings|
      # Turn all caching off by default for tests.
      settings['cache_cycletime_calculations'] = false
    end
  end

  # return a cycletime config that always uses creation and last_resolution
  def default_cycletime_config
    today = Date.parse('2021-12-17')

    block = lambda do |_|
      # instance_eval'd against a CycleTimeConfig, so unqualified helper names do not resolve here
      start_at lambda { |issue|
        MockChangeItem.new(
          field: 'status', value: 'fake', value_id: 1_000_000, time: issue.created
        ).to_change_item
      }
      stop_at last_resolution
    end
    CycleTimeConfig.new(
      possible_statuses: nil, label: 'default', block: block, today: today, settings: load_settings
    )
  end

  # Duplicated from ChartBase. Should this be in a module?
  def chart_format object
    if object.is_a? Time
      # "2022-04-09T11:38:30-07:00"
      object.strftime '%Y-%m-%dT%H:%M:%S%z'
    else
      object.to_s
    end
  end

  # Create a Time from the input string. Supported formats are below. When a timezone isn't specified,
  # it uses UTC rather than local so that all tests will continue to work, regardless of what timezone
  # they're run in.
  # 2024-01-01
  # 2024-01-01T12:34:56
  # 2024-01-01T12:34:56.789
  # 2024-01-01T12:34:56.789+00:00
  # 2024-01-01T12:34:56+00:00
  def empty_config_block
    ->(_) {}
  end

  def create_issue_from_aging_data board:, ages_by_column:, today:, key: 'SP-1'
    today = to_date(today)

    # The ages_by_column may not contain data for all columns so we only look at the ones we do know something about
    columns = board.visible_columns[0..(ages_by_column.size - 1)]

    status_changes = []

    date = today
    (ages_by_column.size - 1).downto(0) do |index|
      next if ages_by_column[index].zero?

      date -= (ages_by_column[index] - 1)
      status_changes << [columns[index], date]
    end

    issue = MockIssue.empty created: date.to_s, board: board, key: key

    # The incrementing hour is required because we can otherwise generate multiple changes with exactly the same
    # timestamp which becomes ambiguous. Which one was actually first?
    hour = 0
    status_changes.reverse_each do |column, change_date|
      status = board.possible_statuses.find_by_id column.status_ids.min

      # We only care about the last one but if we keep overwriting it, the one that sticks will be the last.
      issue.status = status

      issue.add_change(field: 'status',
        value: status.name, value_id: status.id,
        time: to_time("#{change_date}T0#{hour}:00:00"))
      hour += 1
    end

    issue
  end

  def mock_user display_name:, account_id:, avatar_url:, active: true
    User.new(raw: {
        'self' => "https://improvingflow.atlassian.net/rest/api/2/user?accountId=#{account_id}",
        'accountId' => account_id,
        'accountType' => 'atlassian',
        'avatarUrls' => {
          '48x48' => avatar_url,
          '24x24' => avatar_url,
          '16x16' => avatar_url,
          '32x32' => avatar_url
        },
        'displayName' => display_name,
        'active' => active,
        'locale' => 'en_US'
      })
  end

  def deep_copy object
    Marshal.load(Marshal.dump(object))
  end

  ######

  def have_changes expected
    HaveChanges.new expected
  end

  def match_strings expected
    MatchStrings.new(expected)
  end
end

# Separate from the block above because a module has to exist before it can be included, and
# SpecHelpers is defined between the two.
RSpec.configure do |config|
  config.include SpecHelpers
  config.include JiraMetrics::Testing
end
