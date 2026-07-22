# frozen_string_literal: true

require './spec/spec_helper'

describe MockChangeItem do
  let(:board) { board_with_blocked_stalled_statuses }
  let(:issue) { empty_issue created: '2021-01-01', board: board }

  # The validations only run for a status change tied to an issue's board. mock_change builds a
  # MockChangeItem and calls to_change_item, which is where the checks fire. In this board:
  # Backlog=1, In Progress=5, Done=9.
  def status_change(**opts)
    mock_change(issue: issue, field: 'status', time: '2021-01-01', **opts)
  end

  it 'passes a well-formed status change through' do
    expect { status_change value: 'Done', value_id: 9, old_value: 'Backlog', old_value_id: 1 }.not_to raise_error
  end

  describe 'a status name with no id' do
    it 'raises with the guessed ids when the name is known' do
      expect { status_change value: 'Done' }.to raise_error(
        /ID was not specified for new status "Done"\. Perhaps you meant one of \[9\]/
      )
    end

    it 'raises listing the board statuses when the name is unknown' do
      expect { status_change value: 'Bogus' }.to raise_error(
        /No statuses with name "Bogus" but did find these/
      )
    end

    it 'raises for an old status name given without an id' do
      expect { status_change value: 'Done', value_id: 9, old_value: 'Backlog' }.to raise_error(
        /ID was not specified for old status "Backlog"\. Perhaps you meant one of \[1\]/
      )
    end
  end

  describe 'a status id that does not line up with the board' do
    it 'raises when the new status id is not on the board' do
      expect { status_change value: 'Done', value_id: 99_999 }.to raise_error(
        /No status found for id: 99999 \("Done"\)/
      )
    end

    it "raises when the new status id's name doesn't match" do
      expect { status_change value: 'Done', value_id: 1 }.to raise_error(
        /Value passed to mock_change \("Done":1\) doesn't match the status found in the board/
      )
    end

    it "raises when the old status id's name doesn't match" do
      expect { status_change value: 'Done', value_id: 9, old_value: 'Backlog', old_value_id: 5 }.to raise_error(
        /Old value passed to mock_change \("Backlog":5\) doesn't match the status found in the board/
      )
    end
  end
end
