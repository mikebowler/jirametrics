# frozen_string_literal: true

# RSpec.configure do |config|
#   config.formatter = :html
# end

ENV['RACK_ENV'] = 'test'

# simplecov depends on date_core, a C extension that JRuby cannot load.
# Skip it in subprocess spec runs (see the leaked-SystemExit regression test) so the
# child process doesn't restart coverage and pollute its output.
if RUBY_ENGINE == 'ruby' && !ENV['JIRAMETRICS_SUBPROCESS_SPEC']
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
  # pass — their `expect { ... }.to raise_error(SystemExit)` rescues the exit before this hook.
  config.around do |example|
    example.run
  rescue SystemExit => e
    raise "Example leaked a SystemExit (exit status #{e.status}). A production " \
          'exit()/abort() call escaped the example and would otherwise terminate the whole ' \
          'suite early. Wrap the code under test in `expect { ... }.to raise_error(SystemExit)`, ' \
          'or stop it reaching the exit.'
  end
end

def file_read filename
  File.read filename, encoding: 'UTF-8'
end

def sample_board
  statuses = load_statuses './spec/testdata/sample_statuses.json'
  board = Board.new(
    raw: JSON.parse(file_read('spec/testdata/sample_board_1_configuration.json')),
    possible_statuses: statuses
  )
  board.project_config = ProjectConfig.new(
    exporter: Exporter.new, target_path: 'spec/testdata/', jira_config: nil, block: nil
  )
  board
end

# A board whose statuses are replaced with a fixed, known set (ids 1-15) so blocked/stalled tests
# can reference them by name (in the blocked_statuses/stalled_statuses settings) and by id (in
# add_mock_change value_ids). Pass a project_config when the surrounding spec needs to share it;
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
  issue = Issue.new(raw: JSON.parse(file_read("spec/testdata/#{key}.json")), board: board)
  issue.raw['exporter'] = 1 # Make it look like this issue was actually loaded from Jira. Ie not artificial.
  issue
end

def empty_issue created:, board: sample_board, key: 'SP-1', creation_status: nil
  if creation_status.nil?
    backlog_statuses = board.possible_statuses.find_all_by_name('Backlog')
    raise 'No Backlog status found' if backlog_statuses.empty?

    creation_status = [backlog_statuses.first.name, backlog_statuses.first.id]
  elsif creation_status.is_a? Status
    creation_status = [creation_status.name, creation_status.id]
  end

  Issue.new(
    raw: {
      'key' => key,
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => to_time(created).to_s,
        'updated' => to_time(created).to_s,
        'status' => {
          'name' => creation_status[0],
          'id' => creation_status[1].to_s,
          'statusCategory' => {
            'name' => 'To Do',
            'id' => 100,
            'key' => 'new'
          }
        },
        'priority' => {
          'name' => 'Medium',
          'id' => '3'
        },
        'issuetype' => {
          'name' => 'Bug'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        },
        'summary' => 'Do the thing'
      }
    },
    board: board
  )
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
  json = JSON.parse(file_read('./spec/complete_sample/sample_board_1_configuration.json'))
  board = Board.new raw: json, possible_statuses: load_complete_sample_statuses
  board.project_config = ProjectConfig.new(
    exporter: Exporter.new, target_path: 'spec/testdata/', jira_config: nil, block: nil
  )

  board
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
  statuses = StatusCollection.new

  json = JSON.parse(File.read(input_file))
  json.each do |status_config|
    statuses << Status.from_raw(status_config)
  end
  statuses
end

def add_mock_change(
  issue:, field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil,
  artificial: false, field_id: nil
)
  change = mock_change(
    issue: issue,
    field: field, time: time,
    value: value, value_id: value_id,
    old_value: old_value, old_value_id: old_value_id,
    artificial: artificial,
    field_id: field_id
  )
  issue.changes << change
  change
end

# If either value or old_value are statuses then the name and id will be pulled from that object
def mock_change(
  field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil,
  artificial: false, issue: nil, field_id: nil
)
  MockChangeItem.new(
    field: field, value: value, time: time.is_a?(String) ? to_time(time) : time,
    value_id: value_id, old_value: old_value, old_value_id: old_value_id,
    artificial: artificial, issue: issue, field_id: field_id
  ).to_change_item
end

def load_settings
  JSON.parse(File.read('./lib/jirametrics/settings.json')).tap do |settings|
    # Turn all caching off by default for tests.
    settings['cache_cycletime_calculations'] = false
  end
end

def mock_cycletime_config stub_values: []
  MockCycleTimeConfig.new stub_values: stub_values
end

# return a cycletime config that always uses creation and last_resolution
def default_cycletime_config
  today = Date.parse('2021-12-17')

  block = lambda do |_|
    start_at ->(issue) { mock_change field: 'status', value: 'fake', value_id: 1_000_000, time: issue.created }
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
def to_time input
  regex = /
    ^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})
    (?<remainder>T(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})(?<fraction>\.\d+)?
    \s*(?<offset>[+-]\d{2}:?\d{2})?)?$
  /x
  matches = input.match regex
  raise "Can't parse string: #{input.inspect}" unless matches

  adjusted = format(
    '%<year>04d-%<month>02d-%<day>02dT-%<hour>02d:%<minute>02d:%<second>02d%<fraction>s%<offset>s',
    year: matches[:year].to_i,
    month: matches[:month].to_i,
    day: matches[:day].to_i,
    hour: (matches[:hour] || 0).to_i,
    minute: (matches[:minute] || 0).to_i,
    second: (matches[:second] || 0).to_i,
    fraction: matches[:fraction] || '',
    offset: matches[:offset] || '+0000'
  )

  Time.parse adjusted
end

def to_date string
  Date.parse string
end

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

  issue = empty_issue created: date.to_s, board: board, key: key

  # The incrementing hour is required because we can otherwise generate multiple changes with exactly the same
  # timestamp which becomes ambiguous. Which one was actually first?
  hour = 0
  status_changes.reverse_each do |column, change_date|
    status = board.possible_statuses.find_by_id column.status_ids.min

    # We only care about the last one but if we keep overwriting it, the one that sticks will be the last.
    issue.status = status

    add_mock_change(
      issue: issue, field: 'status',
      value: status.name, value_id: status.id,
      time: to_time("#{change_date}T0#{hour}:00:00")
    )
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

def match_strings expected
  MatchStrings.new(expected)
end
