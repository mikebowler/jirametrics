# frozen_string_literal: true

# An Issue you can build without a fixture file and then add history to.
#
# Shipped rather than kept in spec/ so that anyone writing their own charts can test them. Not
# documented, and not something we announce.
#
# MockIssue.new keeps Issue's own signature (raw:, board:) so that a MockIssue is substitutable for
# an Issue everywhere, including MockCycleTimeConfig's is_a?(Issue) check. The friendly constructor
# is MockIssue.empty, which builds the minimal raw hash for you.
class MockIssue < Issue
  # Generated keys start well clear of the hand-written SP-1 and SP-2 that fixtures use.
  FIRST_GENERATED_KEY_NUMBER = 1000

  # Most tests do not care when an issue was created, and making them say so is the friction
  # that pushed people towards load_issue 'SP-1' and its accidental coupling to that fixture.
  #
  # A leap day on purpose. Anything that does its own date arithmetic, assumes 365-day years, or
  # round-trips through a format that cannot represent Feb 29 will trip over this default rather
  # than sailing past on a date that hides the bug.
  DEFAULT_CREATED = '2024-02-29'

  # The change is built and appended in one step, and returned for tests that need to hold on to it.
  # The old add_mock_change took the issue as an argument, so nothing tied a change to the issue it
  # belonged to except the caller's care.
  def add_change field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil,
    artificial: false, field_id: nil
    change = MockChangeItem.new(
      issue: self, field: field, time: time, value: value, value_id: value_id,
      old_value: old_value, old_value_id: old_value_id, artificial: artificial, field_id: field_id
    ).to_change_item
    changes << change
    change
  end

  class << self
    # board has no default. Supplying one would mean either packaging a sample board or reading
    # from this repo's spec directory, and neither belongs in a shipped gem. MockBoard.load builds
    # one from the files jirametrics already downloads.
    def empty board:, created: DEFAULT_CREATED, key: nil, creation_status: nil,
      current_sprint_ids: nil
      new(
        raw: raw_for(
          created: created,
          key: key || next_generated_key,
          creation_status: resolve_creation_status(creation_status, board),
          current_sprint_ids: current_sprint_ids,
          board_id: board.id
        ),
        board: board
      )
    end

    private

    def next_generated_key
      @next_key_number ||= FIRST_GENERATED_KEY_NUMBER
      "SP-#{@next_key_number}".tap { @next_key_number += 1 }
    end

    # A Status carries its category, so the issue cannot end up claiming to be Done while sitting in
    # To Do. Specs that need a status the board does not have can build one with Status.new, which
    # is explicit about being artificial rather than being smuggled in as a name and id.
    def resolve_creation_status creation_status, board
      return creation_status if creation_status.is_a? Status

      raise "creation_status must be a Status, got #{creation_status.class}" unless creation_status.nil?

      backlog_statuses = board.possible_statuses.find_all_by_name('Backlog')
      raise 'No Backlog status found' if backlog_statuses.empty?

      backlog_statuses.first
    end

    # Mimics an issue created directly inside a sprint: that membership lives only in the current
    # Sprint custom field and never appears as a changelog transition.
    #
    # Only two keys are ever read back. Issue#current_sprint_ids takes the ids, and
    # Issue#sprint_field_id finds the sprint field by looking for an array of hashes carrying a
    # boardId. Anything else written here would be decoration that could contradict the board.
    def raw_for created:, key:, creation_status:, current_sprint_ids:, board_id:
      sprint_field =
        if current_sprint_ids
          { 'customfield_10020' => current_sprint_ids.collect { |id| { 'id' => id, 'boardId' => board_id } } }
        else
          {}
        end
      created_time = MockChangeItem.parse_time(created).to_s
      {
        'key' => key,
        'changelog' => { 'histories' => [] },
        'fields' => sprint_field.merge(
          'created' => created_time,
          'updated' => created_time,
          'status' => {
            'name' => creation_status.name,
            'id' => creation_status.id.to_s,
            'statusCategory' => {
              'name' => creation_status.category.name,
              'id' => creation_status.category.id,
              'key' => creation_status.category.key
            }
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
