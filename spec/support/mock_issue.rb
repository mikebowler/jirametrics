# frozen_string_literal: true

# An Issue you can build without a fixture file and then add history to.
#
# MockIssue.new keeps Issue's own signature (raw:, board:) so that a MockIssue is substitutable for
# an Issue everywhere, including MockCycleTimeConfig's is_a?(Issue) check. The friendly constructor
# is MockIssue.empty, which builds the minimal raw hash for you.
class MockIssue < Issue
  # Generated keys start well clear of the hand-written SP-1 and SP-2 that fixtures use.
  FIRST_GENERATED_KEY_NUMBER = 1000

  # Most tests do not care when an issue was created, and making them say so is the friction
  # that pushed people towards load_issue 'SP-1' and its accidental coupling to that fixture.
  DEFAULT_CREATED = '2024-01-01'

  class << self
    # Reset between examples so a generated key never depends on how many issues earlier tests
    # happened to build. Without this, random ordering makes keys vary by seed.
    def reset_generated_keys
      @next_key_number = FIRST_GENERATED_KEY_NUMBER
    end

    def next_generated_key
      @next_key_number ||= FIRST_GENERATED_KEY_NUMBER
      "SP-#{@next_key_number}".tap { @next_key_number += 1 }
    end

    def empty created: DEFAULT_CREATED, board: SpecHelpers.sample_board, key: nil, creation_status: nil,
      current_sprints: nil, changelog_histories: []
      new(
        raw: raw_for(
          created: created,
          key: key || next_generated_key,
          creation_status: resolve_creation_status(creation_status, board),
          current_sprints: current_sprints,
          changelog_histories: changelog_histories
        ),
        board: board
      )
    end

    def resolve_creation_status creation_status, board
      return [creation_status.name, creation_status.id] if creation_status.is_a? Status
      return creation_status unless creation_status.nil?

      backlog_statuses = board.possible_statuses.find_all_by_name('Backlog')
      raise 'No Backlog status found' if backlog_statuses.empty?

      [backlog_statuses.first.name, backlog_statuses.first.id]
    end

    # current_sprints mimics an issue created directly inside a sprint: that membership lives only in
    # the current Sprint custom field and never appears as a changelog transition.
    def raw_for created:, key:, creation_status:, current_sprints:, changelog_histories:
      sprint_field = current_sprints ? { 'customfield_10020' => current_sprints } : {}
      created_time = SpecHelpers.to_time(created).to_s
      {
        'key' => key,
        'changelog' => { 'histories' => changelog_histories },
        'fields' => sprint_field.merge(
          'created' => created_time,
          'updated' => created_time,
          'status' => {
            'name' => creation_status[0],
            'id' => creation_status[1].to_s,
            'statusCategory' => { 'name' => 'To Do', 'id' => 100, 'key' => 'new' }
          },
          'priority' => { 'name' => 'Medium', 'id' => '3' },
          'issuetype' => { 'name' => 'Bug' },
          'creator' => { 'displayName' => 'Tolkien' },
          'summary' => 'Do the thing'
        )
      }
    end
  end
end
