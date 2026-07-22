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
    # Status names are deliberately left alone. They show up throughout the reports (hover text, aging
    # tables, the board columns themselves), so scrubbing them to tokens would make those displays
    # useless -- you'd lose the workflow story that makes the report worth reading. If a client's status
    # vocabulary is itself confidential, rename the statuses in Jira rather than anonymizing here.
    anonymize_board_names
    anonymize_labels_and_components
    anonymize_sprints
    anonymize_fix_versions
    anonymize_server_url
    shift_all_dates unless @date_adjustment.zero?
    @file_system.log 'Anonymize done'
  end

  def random_phrase
    # RandomWord periodically blows up for no reason we can determine. If it throws an exception then
    # just try again. In every case we've seen, it's worked on the second attempt, but we'll be
    # cautious and try five times.
    5.times do |i|
      return RandomWord.phrases.next.tr('_', ' ')
    rescue # rubocop:disable Style/RescueStandardError
      @file_system.log "Random word blew up on attempt #{i + 1}"
    end
  end

  def anonymize_issue_keys_and_titles issues: @issues
    counter = 0
    seen_author_raws = {}.compare_by_identity
    issues.each do |issue|
      issue.raw['key'] = "ANON-#{counter += 1}"
      anonymize_issue_summary_fields issue
      anonymize_author_raw issue.raw['fields']['creator'], seen_author_raws
      anonymize_change_content issue, seen_author_raws

      issue.issue_links.each do |link|
        other_issue = link.other_issue
        next if other_issue.key.match?(/^ANON-\d+$/) # Already anonymized?

        other_issue.raw['key'] = "ANON-#{counter += 1}"
        other_issue.raw['fields']['summary'] = random_phrase
      end
    end
  end

  def anonymize_issue_summary_fields issue
    issue.raw['fields']['summary'] = random_phrase
    issue.raw['fields']['description'] = nil
    return if issue.raw['fields']['assignee'].nil?

    issue.raw['fields']['assignee']['displayName'] = random_name
  end

  def anonymize_change_content issue, seen_author_raws
    issue.changes.each do |change|
      anonymize_author_raw change.author_raw, seen_author_raws
      next unless change.comment? || change.description?

      change.value = nil
      change.old_value = nil
    end
  end

  def anonymize_labels_and_components
    @issues.each do |issue|
      issue.raw['fields']['labels'] = []
      issue.raw['fields']['components'] = []
    end
  end

  def anonymize_sprints
    sprint_counter = 0
    sprint_name_map = {}
    @all_boards.each_value do |board|
      board.sprints.each do |sprint|
        name = sprint.raw['name']
        unless sprint_name_map[name]
          sprint_counter += 1
          sprint_name_map[name] = "Sprint-#{sprint_counter}"
        end
        sprint.raw['name'] = sprint_name_map[name]
      end
    end
  end

  def anonymize_fix_versions
    version_counter = 0
    version_name_map = {}
    @issues.each do |issue|
      issue.raw['fields']['fixVersions']&.each do |fix_version|
        name = fix_version['name']
        unless version_name_map[name]
          version_counter += 1
          version_name_map[name] = "Version-#{version_counter}"
        end
        fix_version['name'] = version_name_map[name]
      end
    end
  end

  def anonymize_server_url
    @all_boards.each_value do |board|
      board.raw['self'] = board.raw['self']&.sub(%r{^https?://[^/]+}, 'https://anon.example.com')
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
    @project_config.time_range = (range.begin + adjustment_in_seconds)..(range.end + adjustment_in_seconds)
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

  private

  def anonymize_author_raw author_raw, seen
    return unless author_raw
    return if seen[author_raw]

    seen[author_raw] = true
    name = random_name
    author_raw['displayName'] = name
    author_raw['name'] = name
    author_raw.delete('emailAddress')
    author_raw.delete('avatarUrls')
  end
end
