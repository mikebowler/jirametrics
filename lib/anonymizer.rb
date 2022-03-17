# frozen_string_literal: true

require 'random-word'

class Anonymizer
  def initialize project_config:, date_adjustment: -200
    @project_config = project_config
    @issues = @project_config.issues
    @all_board_metadata = @project_config.all_board_columns
    @possible_statuses = @project_config.possible_statuses
    @date_adjustment = date_adjustment
  end

  def run
    anonymize_issue_keys_and_titles
    anonymize_column_names
    anonymize_issue_statuses
    shift_all_dates unless @date_adjustment.zero?
    puts 'Anonymize done'
  end

  def anonymize_issue_keys_and_titles
    puts 'Anonymizing issue ids and descriptions'
    counter = 1
    @issues.each do |issue|
      new_key = "ANON-#{counter += 1}"

      issue.raw['key'] = new_key
      issue.raw['fields']['summary'] = RandomWord.phrases.next.gsub(/_/, ' ')
      issue.raw['fields']['assignee']['displayName'] = random_name unless issue.raw['fields']['assignee'].nil?
    end
  end

  def anonymize_column_names
    @all_board_metadata.each_key do |board_id|
      puts "Anonymizing column names for board #{board_id}"

      column_name = 'Column-A'
      @all_board_metadata[board_id].each do |column|
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
        status_key = "#{issue.type}-#{change.value}"
        if status_name_hash[status_key].nil?
          status_name_hash[status_key] = "#{issue.type.downcase}-status-#{next_status}"
          next_status = next_status.next
        end
      end
    end

    @possible_statuses.each do |status|
      status_key = "#{status.type}-#{status.name}"
      if status_name_hash[status_key].nil?
        status_name_hash[status_key] = "#{status.type.downcase}-status-#{next_status}"
        next_status = next_status.next
      end
    end

    status_name_hash
  end

  def anonymize_issue_statuses
    puts 'Anonymizing issue statuses and status categories'
    status_name_hash = build_status_name_hash

    @issues.each do |issue|
      # This is where we create URL's from
      issue.raw['self'] = nil

      issue.changes.each do |change|
        next unless change.status?

        status_key = "#{issue.type}-#{change.value}"
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.value = anonymized_value

        next if change.old_value.nil?

        status_key = "#{issue.type}-#{change.old_value}"
        anonymized_value = status_name_hash[status_key]
        raise "status_name_hash[#{status_key.inspect} is nil" if anonymized_value.nil?

        change.old_value = anonymized_value
      end
    end

    @possible_statuses.each do |status|
      status_key = "#{status.type}-#{status.name}"
      if status_name_hash[status_key].nil?
        raise "Can't find status_key #{status_key.inspect} in #{status_name_hash.inspect}"
      end

      status.name = status_name_hash[status_key] unless status_name_hash[status_key].nil?
    end
  end

  def shift_all_dates
    puts "Shifting all dates by #{@date_adjustment} days"
    @issues.each do |issue|
      issue.changes.each do |change|
        change.time = change.time + @date_adjustment
      end

      issue.raw['fields']['updated'] = (issue.updated + @date_adjustment).to_s
    end

    range = @project_config.time_range
    @project_config.time_range = (range.begin + @date_adjustment)..(range.end + @date_adjustment)
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
end
