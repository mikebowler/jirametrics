# frozen_string_literal: true

class DataQualityReport
  attr_accessor :issues, :cycletime

  class Entry
    attr_reader :started, :stopped, :issue, :problems

    def initialize started:, stopped:, issue:
      @started = started
      @stopped = stopped
      @issue = issue
      @problems = []
    end

    def report problem:, impact:
      @problems << [problem, impact]
    end
  end

  def run
    initialize_entries

    scan_for_completed_issues_without_a_start_time
    scan_for_status_change_after_done
    scan_for_backwards_movement

    create_results_html
  end

  # Return a format that's easier to assert against
  def testable_entries
    @entries.collect { |entry| [entry.started.to_s, entry.stopped.to_s, entry.issue] }
  end

  def testable_problems
    @entries.collect do |entry|
      [entry.issue.key, problems.inspect]
    end
    # @entries.collect { |entry| [entry.started.to_s, entry.stopped.to_s, entry.issue] }
  end

  def entries_with_problems
    @entries.reject { |entry| entry.problems.empty? }
  end

  def create_results_html
    entries_with_problems = entries_with_problems()
    return '' if entries_with_problems.empty?

    result = String.new
    result << '<h1>Data Quality issues</h1>'
    percentage = (entries_with_problems.size * 100.0 / @entries.size).round(1)
    result << "Out of a total of #{@entries.size} issues, #{entries_with_problems.size} have one"
    result << " or more problems related to data quality (#{percentage}%). Do you trust this data?"
    result << '<ol>'
    entries_with_problems.each do |entry|
      result << '<li><b>' << entry.issue.key << ':</b> <i>' << entry.issue.summary << '</i>'
      result << '<dl>'
      entry.problems.each do |problem, impact|
        result << "<dt>Problem: #{problem}</dt><dd>Impact: #{impact}</dd>"
      end
      result << '</dl></li>'
    end
    result << '</ol>'
    result
  end

  def initialize_entries
    @entries = @issues.collect do |issue|
      Entry.new(
        started: @cycletime.started_time(issue),
        stopped: @cycletime.stopped_time(issue),
        issue: issue
      )
    end

    @entries.sort! do |a, b|
      a.issue.key =~ /.+-(\d+)$/
      a_id = $1.to_i

      b.issue.key =~ /.+-(\d+)$/
      b_id = $1.to_i

      a_id <=> b_id
    end
  end

  def scan_for_completed_issues_without_a_start_time
    @entries.each do |entry|
      next unless entry.stopped && entry.started.nil?

      entry.report(
        problem: 'Item has finished but no start time can be found',
        impact: 'Item will not show up in cycletime or WIP calculations'
      )
    end
  end

  def scan_for_status_change_after_done
    @entries.each do |entry|
      next unless entry.stopped

      changes_after_done = entry.issue.changes.select do |change|
        change.status? && change.time > entry.stopped
      end

      puts "changes_after_done=#{changes_after_done}"
      unless changes_after_done.empty?
        problem = "This item was done on #{entry.stopped} but status changes continued after that."
        changes_after_done.each do |change|
          problem << " Status change to #{change.value} on #{change.time}."
        end
        entry.report(
          problem: problem,
          impact: 'This likely indicates an incorrect end date and will impact cycletime and WIP calculations'
        )
      end
    end
  end

  def scan_for_backwards_movement
  end
end
