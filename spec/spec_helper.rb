# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  SimpleCov.add_filter do |src_file|
    File.basename(src_file.filename) == 'config.rb'
  end
end

require 'require_all'
require_all 'lib'

def make_test_filename basename
  "spec/tmp/#{basename}"
end

def sample_board
  statuses = StatusCollection.new
  statuses << Status.new(name: 'Backlog', id: 1, category_name: 'To Do', category_id: 2)
  statuses << Status.new(name: 'Doing', id: 3, category_name: 'In Progress', category_id: 4)
  statuses << Status.new(name: 'Done', id: 5, category_name: 'Done', category_id: 6)

  Board.new raw: JSON.parse(File.read('spec/testdata/sample_board_1_configuration.json')), possible_statuses: statuses
end

def load_issue key, board: nil
  board = sample_board if board.nil?
  Issue.new(raw: JSON.parse(File.read("spec/testdata/#{key}.json")), board: board)
end

def empty_issue created:, board: sample_board
  Issue.new(
    raw: {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => to_time(created).to_s,
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        },
        'issuetype' => {
          'name' => 'Bug'
        },
        'creator' => {
          'displayName' => 'Tolkien'
        }
      }
    },
    board: board
  )
end

def default_cycletime_config
  today = Date.parse('2021-12-17')

  block = lambda do |_|
    start_at created
    stop_at last_resolution
  end
  CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today
end

def load_complete_sample_issues board:
  result = []
  Dir.each_child './spec/complete_sample/sample_issues' do |file|
    next unless file =~ /SP-.+/

    result << Issue.new(raw: JSON.parse(File.read("./spec/complete_sample/sample_issues/#{file}")), board: board)
  end

  # Sort them back into the order they would have come from Jira because some of the tests are order dependant.
  result.sort_by(&:key_as_i).reverse
end

def load_complete_sample_board
  json = JSON.parse(File.read('./spec/complete_sample/sample_board_1_configuration.json'))
  Board.new raw: json, possible_statuses: load_complete_sample_statuses
end

def load_complete_sample_statuses
  statuses = StatusCollection.new

  json = JSON.parse(File.read('./spec/complete_sample/sample_statuses.json'))
  json.each do |type_config|
    type_config['statuses'].each do |status_config|
      category_config = status_config['statusCategory']
      statuses << Status.new(
        name: status_config['name'], id: status_config['id'],
        category_name: category_config['name'], category_id: category_config['id']
      )
    end
  end
  statuses
end

def load_complete_sample_date_range
  to_time('2021-09-14T00:00:00+00:00')..to_time('2021-12-13T23:59:59+00:00')
end

def mock_change field:, value:, time:, value_id: 2, old_value: nil, old_value_id: nil, artificial: false
  time = to_time(time) if time.is_a? String
  ChangeItem.new time: time, author: 'Tolkien', artificial: artificial, raw: {
    'field' => field,
    'to' => value_id,
    'toString' => value,
    'from' => old_value_id,
    'fromString' => old_value
  }
end

def mock_cycletime_config stub_values: []
  raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

  stub_values.each do |line|

    unless line[0].is_a? Issue
      raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
    end

    line[1] = to_time(line[1]) if line[1].is_a? String
    line[2] = to_time(line[2]) if line[2].is_a? String
  end

  config = CycleTimeConfig.new parent_config: nil, label: nil, block: nil
  config.start_at ->(issue) { stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](1) }
  config.stop_at  ->(issue) { stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](2) }
  config
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

def to_time string
  if string =~ /^(\d{4})-(\d{2})-(\d{2})$/
    Time.new $1.to_i, $2.to_i, $3.to_i, 0, 0, 0, '+00:00'
  elsif string =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/
    Time.new $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, '+00:00'
  else
    Time.parse string
  end
end

def to_date string
  Date.parse string
end
