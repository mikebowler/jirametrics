# frozen_string_literal: true

require 'random-word'
require 'require_all'
require_all 'lib'

def to_time date
  Time.new date.year, date.month, date.day, rand(0..23), rand(0..59), rand(0..59)
  # Time.new date.year, date.month, date.day, 0, 0, 0
end

class FakeIssue
  @@issue_number = 1
  attr_reader :effort, :raw, :worker

  def initialize date:, type:, worker:
    @raw = {
      key: "FAKE-#{@@issue_number += 1}",
      changelog: {
        histories: []
      },
      fields: {
        created: to_time(date).to_s,
        updated: to_time(date).to_s,
        creator: {
          displayName: 'George Jetson'
        },
        issuetype: {
          name: type
        },
        status: {
          name: 'To Do',
          id: 1,
          statusCategory: {
            id: 2,
            name: 'To Do'
          }
        },
        priority: {
          name: ''
        },
        summary: RandomWord.phrases.next.gsub(/_/, ' '),
        issuelinks: []
      }
    }

    @workers = [worker]
    @effort = case type
    when 'Story'
      [1, 2, 3, 3, 3, 3, 4, 4, 4, 5, 6].sample
    else
      [1, 2, 3].sample
    end
    unblock
    @done = false
    @last_status = 'To Do'
    @last_status_id = 1
    change_status new_status: 'In Progress', new_status_id: 3, date: date
  end

  def blocked? = @blocked
  def block = @blocked = true
  def unblock = @blocked = false

  def key = @raw[:key]

  def do_work date:, effort:
    raise 'Already done' if done?

    @effort -= effort
    return unless done?

    change_status new_status: 'Done', new_status_id: 5, date: date
    fix_change_timestamps
  end

  def fix_change_timestamps
    # since the timestamps have random hours, it's possible for them to be issued out of order. Sort them now
    changes = @raw[:changelog][:histories]
    times = changes.collect { |change| change[:created] }.sort

    changes.each do |change|
      change[:created] = times.shift
    end
  end

  def done? = @effort <= 0

  def change_status date:, new_status:, new_status_id:
    @raw[:changelog][:histories] << {
      author: {
        emailAddress: 'george@jetson.com',
        displayName: 'George Jetson'
      },
      created: to_time(date),
      items: [
        {
          field: 'status',
          fieldtype: 'jira',
          fieldId: 'status',
          from: @last_status_id,
          fromString: @last_status,
          to: new_status_id,
          toString: new_status
        }
      ]
    }

    @last_status = new_status
    @last_status_id = new_status_id

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
    remove_old_files
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
  end

  def remove_old_files
    path = "#{@target_path}#{@file_prefix}_issues"
    Dir.foreach path do |file|
      next unless file =~ /-\d+\.json$/

      filename = "#{path}/#{file}"
      File.unlink filename
    end
  end

  def lucky? probability
    @random.rand(1..100) <= probability
  end

  def next_issue_for worker:, date:, type:
    # First look for something I already started
    issue = @issues.find { |issue| issue.worker == worker && !issue.done? && !issue.blocked? }

    # Then look for something that someone else started

    # Then start new work
    issue = FakeIssue.new(date: date, type: type, worker: worker) if issue.nil?

    issue
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
      if worker.issue.nil? || worker.issue.done?
        type = lucky?(89) ? 'Story' : 'Bug'
        worker.issue = next_issue_for worker: worker, date: date, type: type
        @issues << worker.issue
      end

      worker.issue = next_issue_for worker: worker, date: date, type: type if worker.issue.blocked?
      worker.issue.do_work date: date, effort: worker_capacity
      worker.issue = nil if worker.issue.done?
    end
  end
end

Generator.new.run
