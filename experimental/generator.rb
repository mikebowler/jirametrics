# frozen_string_literal: true

require 'random-word'
require 'require_all'
require_all 'lib'

class FakeIssue
  @@issue_number = 1
  attr_reader :effort, :raw

  def initialize date:, type:
    @raw = {
      key: "SP-#{@@issue_number += 1}",
      changelog: {
        histories: []
      },
      fields: {
        created: date.to_time.to_s,
        updated: date.to_time.to_s,
        creator: {
          displayName: 'George Jetson'
        },
        issuetype: {
          name: type
        },
        status: {
          name: 'ToDo',
          id: 1,
          statusCategory: {
            id: 2,
            name: 'ToDo'
          }
        },
        priority: {
          name: ''
        },
        summary: RandomWord.phrases.next.gsub(/_/, ' '),
        issuelinks: []
      }
    }


    @effort = [1, 2, 3, 3, 3, 3, 4, 4, 4, 5, 6].sample
    unblock
    @done = false
    @last_status = nil
    change_status new_status: 'In Progress', date: date
  end

  def blocked? = @blocked
  def block = @blocked = true
  def unblock = @blocked = false

  def key = @raw[:key]

  def do_work date:, effort:
    raise 'Already done' if done?

    @effort -= effort
    change_status new_status: 'Done', date: date if done?
  end

  def done? = @effort <= 0

  def change_status date:, new_status:
    @raw[:changelog][:histories] << {
      author: {
        emailAddress: 'george@jetson.com',
        displayName: 'George Jetson'
      },
      created: date.to_time,
      items: [
        {
          field: 'status',
          fieldtype: 'jira',
          fieldId: 'status',
          from: 1,
          fromString: @last_status || 'ToDo',
          to: 2,
          toString: new_status
        }
      ]
    }
    @last_status = new_status

  end
end

class Worker
  attr_accessor :issue
end

class Generator
  def initialize
    @random = Random.new
    @file_prefix = 'fake'
    @target_path = 'target/'

    # @probability_work_will_be_pushed = 20
    @probability_unblocked_work_becomes_blocked = 20
    @probability_blocked_work_becomes_unblocked = 20
    @date_range = (Date.today - 500)..Date.today
    @issues = []
    @workers = []
    5.times { @workers << Worker.new }
  end

  def run
    @date_range.each_with_index do |date, day|
      yield date, day if block_given?
      process_date(date, day) if (1..5).include? date.wday # Weekday
    end

    @issues.each do |issue|
      File.open "target/fake_issues/#{issue.key}.json", 'w' do |file|
        file.puts JSON.pretty_generate(issue.raw)
      end
    end

    File.open "target/fake_meta.json", 'w' do |file|
      file.puts JSON.pretty_generate({
        time_start: (@date_range.end - 90).to_time,
        time_end: @date_range.end.to_time,
        'no-download': true
      })
    end

    # dump it all to the target directory
  end

  def lucky? probability
    @random.rand(1..100) <= probability
  end

  def process_date date, simulation_day
    @issues.each do |issue|
      if issue.blocked?
        issue.unblock if lucky? @probability_blocked_work_becomes_unblocked
      elsif lucky? @probability_unblocked_work_becomes_blocked
        issue.block
      end
    end

    @workers.each do |worker|
      worker_capacity = [0, 1, 1, 1, 2].sample
      if worker.issue.nil?
        type = lucky?(89) ? 'Story' : 'Bug'
        worker.issue = FakeIssue.new date: date, type: type
        @issues << worker.issue
      end

      worker.issue.do_work date: date, effort: worker_capacity
      worker.issue = nil if worker.issue.done?
    end
  end
end

Generator.new.run
