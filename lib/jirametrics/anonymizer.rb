# frozen_string_literal: true

require 'random-word'

class Anonymizer < ChartBase
  # needed for testing
  attr_reader :project_config, :issues

  def initialize project_config:, date_adjustment: -200
    super()
    @project_config = project_config
    @issues = @project_config.issues
    @all_boards = @project_config.all_boards
    @possible_statuses = @project_config.possible_statuses
    @date_adjustment = date_adjustment
    @file_system = project_config.exporter.file_system
  end

  def run
    anonymize_issue_keys_and_titles
    anonymize_column_names
    # anonymize_issue_statuses
    anonymize_board_names
    shift_all_dates unless @date_adjustment.zero?
    @file_system.log 'Anonymize done'
  end

  def random_phrase
    # RandomWord periodically blows up for no reason we can determine. If it throws an exception then
    # just try again. In every case we've seen, it's worked on the second attempt, but we'll be
    # cautious and try five times.
    5.times do |i|
      return RandomWord.phrases.next.tr('_', ' ')
    rescue # rubocop:disable Style/RescueStandardError We don't care what exception was thrown.
      @file_system.log "Random word blew up on attempt #{i + 1}"
    end
  end

  def anonymize_issue_keys_and_titles issues: @issues
    counter = 0
    issues.each do |issue|
      new_key = "ANON-#{counter += 1}"

      issue.raw['key'] = new_key
      issue.raw['fields']['summary'] = random_phrase
      issue.raw['fields']['assignee']['displayName'] = random_name unless issue.raw['fields']['assignee'].nil?

      issue.issue_links.each do |link|
        other_issue = link.other_issue
        next if other_issue.key.match?(/^ANON-\d+$/) # Already anonymized?

        other_issue.raw['key'] = "ANON-#{counter += 1}"
        other_issue.raw['fields']['summary'] = random_phrase
      end
    end
  end

  def anonymize_column_names
    @all_boards.each_key do |board_id|
      @file_system.log "Anonymizing column names for board #{board_id}"

      column_name = 'Column-A'
      @all_boards[board_id].visible_columns.each do |column|
        column.name = column_name
        column_name = column_name.next
      end
    end
  end

  def build_status_name_hash
    next_status = 'a'
    status_name_hash = {}
    @issues.each do |issue|
      issue.changes.each do |change|
        next unless change.status?

        # TODO: Do old value too
        status_key = change.value
        if status_name_hash[status_key].nil?
          status_name_hash[status_key] = "status-#{next_status}"
          next_status = next_status.next
        end
      end
    end

    @possible_statuses.each do |status|
      status_key = status.name
      if status_name_hash[status_key].nil?
        status_name_hash[status_key] = "status-#{next_status}"
        next_status = next_status.next
      end
    end

    status_name_hash
  end

  def anonymize_issue_statuses
    @file_system.log 'Anonymizing issue statuses and status categories'
    status_name_hash = build_status_name_hash

    @issues.each do |issue|
      # This is where we create URL's from
      issue.raw['self'] = nil

      issue.changes.each do |change|
        next unless change.status?

        status_key = change.value
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.value = anonymized_value

        next if change.old_value.nil?

        status_key = change.old_value
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.old_value = anonymized_value
      end
    end

    @possible_statuses.each do |status|
      status_key = status.name
      if status_name_hash[status_key].nil?
        raise "Can't find status_key #{status_key.inspect} in #{status_name_hash.inspect}"
      end

      status.name = status_name_hash[status_key] unless status_name_hash[status_key].nil?
    end
  end

  def shift_all_dates date_adjustment: @date_adjustment
    adjustment_in_seconds = 60 * 60 * 24 * date_adjustment
    @file_system.log "Shifting all dates by #{label_days date_adjustment}"
    @issues.each do |issue|
      issue.changes.each do |change|
        change.time = change.time + adjustment_in_seconds
      end

      issue.raw['fields']['updated'] = (issue.updated + adjustment_in_seconds).to_s
    end

    range = @project_config.time_range
    @project_config.time_range = (range.begin + date_adjustment)..(range.end + date_adjustment)
  end

  def random_name
    # Names generated from https://www.random-name-generator.com
    [
      'Benjamin Pelletier',
      'Levi Scott',
      'Emilia Leblanc',
      'Victoria Singh',
      'Theodore King',
      'Amelia Kelly',
      'Samuel Jones',
      'Lucy Kelly',
      'Oliver Fortin',
      'Riley Murphy',
      'Elijah Stewart',
      'Elizabeth Murphy',
      'Declan Simard',
      'Myles Singh',
      'Jayden Smith',
      'Sophie Richard',
      'Levi Mitchell',
      'Alexander Davis',
      'Sebastian Thompson',
      'Logan Robinson',
      'Madison Girard',
      'Ellie King',
      'Aiden Miller',
      'Ethan Anderson',
      'Scarlett Murray',
      'Audrey Moore',
      'Emmett Reid',
      'Jacob Poirier',
      'Violet MacDonald'
    ].sample
  end

  def anonymize_board_names
    @all_boards.each_value do |board|
      board.raw['name'] = "#{random_phrase} board"
    end
  end
end
