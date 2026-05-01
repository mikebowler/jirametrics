# frozen_string_literal: true

require './spec/spec_helper'

describe ChangeItem do
  let(:time) { Time.parse('2021-09-06T04:33:55.539+0000') }
  let(:later_time) { Time.parse('2022-01-01T00:00:00+0000') }
  let(:status_raw) do
    { 'field' => 'status', 'to' => '5', 'from' => '3', 'toString' => 'In Progress', 'fromString' => 'To Do' }
  end
  let(:status_change) { described_class.new time: time, author_raw: nil, raw: status_raw }

  def change_for(field, to: nil, to_string: 'x', from_string: nil)
    described_class.new time: time, author_raw: nil, raw: {
      'field' => field, 'to' => to, 'toString' => to_string, 'fromString' => from_string
    }
  end

  it 'creates change' do
    change = described_class.new time: time, author_raw: nil, raw: {
      'field' => 'Flagged',
      'fieldtype' => 'custom',
      'fieldId' => 'customfield_10021',
      'from' => nil,
      'fromString' => nil,
      'to' => '[10019]',
      'toString' => 'Blocked'
    }

    expect(change).to be_flagged
    expect(change.field).to eq 'Flagged'
    expect(change.value).to eq 'Blocked'
    expect(change).not_to be_status
    expect(change).not_to be_priority
    expect(change).not_to be_resolution
    expect(change).not_to be_artificial

    expect(change.to_s).to eq(
      'ChangeItem(field: "Flagged", value: "Blocked":0, time: "2021-09-06 04:33:55 +0000", ' \
        'field_id: "customfield_10021")'
    )
  end

  it 'parses multiple ids for Sprint' do
    change = described_class.new time: time, author_raw: nil, raw: {
      'field' => 'Sprint',
      'fieldtype' => 'custom',
      'from' => '2',
      'fromString' => 'Scrum Sprint 10',
      'to' => '2, 3',
      'toString' => 'Scrum Sprint 10, Scrum Sprint 11'
    }

    expect(change).to be_sprint
    expect(change.old_value_id).to eq [2]
    expect(change.value_id).to eq [2, 3]
  end

  it 'supports artificial' do
    change = described_class.new time: time, artificial: true, author_raw: nil, raw: {
      'field' => 'Flagged',
      'fieldtype' => 'custom',
      'fieldId' => 'customfield_10021',
      'from' => nil,
      'fromString' => nil,
      'to' => '[10019]',
      'toString' => 'Blocked'
    }

    expect(change).to be_artificial
    expect(change.to_s).to eq(
      'ChangeItem(field: "Flagged", value: "Blocked":0, time: "2021-09-06 04:33:55 +0000", ' \
      'field_id: "customfield_10021", artificial)'
    )
  end

  context 'initialize' do
    it 'raises when time is nil' do
      expect { described_class.new time: nil, author_raw: nil, raw: status_raw }
        .to raise_error('ChangeItem.new() time cannot be nil')
    end

    it 'raises when time is not a Time object' do
      expect { described_class.new time: '2021-01-01', author_raw: nil, raw: status_raw }
        .to raise_error(/Time must be an object of type Time/)
    end

    it 'stores nil value_id when to is nil for non-sprint fields' do
      expect(change_for('status').value_id).to be_nil
    end

    it 'stores nil old_value_id when from is nil for non-sprint fields' do
      change = described_class.new time: time, author_raw: nil, raw: status_raw.merge('from' => nil)
      expect(change.old_value_id).to be_nil
    end
  end

  context 'author' do
    it 'returns displayName when present' do
      change = described_class.new time: time, author_raw: { 'displayName' => 'Alice', 'name' => 'alice' }, raw: status_raw
      expect(change.author).to eq 'Alice'
    end

    it 'returns name when displayName is absent' do
      change = described_class.new time: time, author_raw: { 'name' => 'alice' }, raw: status_raw
      expect(change.author).to eq 'alice'
    end

    it 'returns "Unknown author" when author_raw is nil' do
      expect(status_change.author).to eq 'Unknown author'
    end
  end

  context 'author_icon_url' do
    it 'returns the 16x16 avatar URL when present' do
      change = described_class.new time: time, author_raw: { 'avatarUrls' => { '16x16' => 'https://example.com/icon.png' } }, raw: status_raw
      expect(change.author_icon_url).to eq 'https://example.com/icon.png'
    end

    it 'returns nil when author_raw is nil' do
      expect(status_change.author_icon_url).to be_nil
    end

    it 'returns nil when avatarUrls is absent' do
      change = described_class.new time: time, author_raw: { 'displayName' => 'Alice' }, raw: status_raw
      expect(change.author_icon_url).to be_nil
    end
  end

  context 'field type predicates' do
    {
      'assignee'     => :assignee?,
      'comment'      => :comment?,
      'description'  => :description?,
      'duedate'      => :due_date?,
      'Fix Version'  => :fix_version?,
      'issuetype'    => :issue_type?,
      'labels'       => :labels?,
      'Link'         => :link?
    }.each do |field, method|
      it "#{method} returns true when field is '#{field}'" do
        expect(change_for(field).send(method)).to be true
      end

      it "#{method} returns false for other fields" do
        expect(change_for('other').send(method)).to be false
      end
    end
  end

  context 'field_as_human_readable' do
    it 'translates duedate' do
      expect(change_for('duedate').field_as_human_readable).to eq 'Due date'
    end

    it 'translates timeestimate' do
      expect(change_for('timeestimate').field_as_human_readable).to eq 'Time estimate'
    end

    it 'translates timeoriginalestimate' do
      expect(change_for('timeoriginalestimate').field_as_human_readable).to eq 'Time original estimate'
    end

    it 'translates issuetype' do
      expect(change_for('issuetype').field_as_human_readable).to eq 'Issue type'
    end

    it 'translates IssueParentAssociation' do
      expect(change_for('IssueParentAssociation').field_as_human_readable).to eq 'Issue parent association'
    end

    it 'capitalizes unknown fields' do
      expect(change_for('status').field_as_human_readable).to eq 'Status'
    end
  end

  context '==' do
    it 'equals another change with the same field, value, and time' do
      other = described_class.new time: time, author_raw: nil, raw: status_raw
      expect(status_change).to eq other
    end

    it 'is not equal when field differs' do
      other = described_class.new time: time, author_raw: nil, raw: status_raw.merge('field' => 'priority')
      expect(status_change).not_to eq other
    end

    it 'is not equal when value differs' do
      other = described_class.new time: time, author_raw: nil, raw: status_raw.merge('toString' => 'Done')
      expect(status_change).not_to eq other
    end

    it 'is not equal when time differs' do
      other = described_class.new time: later_time, author_raw: nil, raw: status_raw
      expect(status_change).not_to eq other
    end
  end

  context 'to_s' do
    it 'includes old_value and old_value_id when present' do
      expect(status_change.to_s).to include('"To Do":3')
    end

    it 'omits value_id when to is nil' do
      change = change_for('status')
      expect(change.to_s).not_to match(/"In Progress":\d/)
    end

    it 'omits old_value when fromString is nil' do
      change = described_class.new time: time, author_raw: nil, raw: status_raw.merge('fromString' => nil)
      expect(change.to_s).not_to include('old_value')
    end
  end

  context 'status_matches' do
    let(:change_item) do
      described_class.new time: time, author_raw: nil, raw: {
        'field' => 'status',
        'from' => 1,
        'fromString' => 'To Do',
        'to' => 2,
        'toString' => 'In Progress'
      }
    end

    context 'current_status_matches' do
      it 'matches on id' do
        expect(change_item.current_status_matches 2).to be_truthy
      end

      it 'matches on String' do
        expect(change_item.current_status_matches 'In Progress').to be_truthy
      end

      it 'matches on Status' do
        status = Status.new(
          name: 'In Progress', id: 2, category_name: 'one', category_id: 3, category_key: 'indeterminate'
        )
        expect(change_item.current_status_matches status).to be_truthy
      end

      it 'returns false when value does not match' do
        expect(change_item.current_status_matches 'Done').to be false
      end

      it 'returns false when field is not status' do
        expect(change_for('priority', to: '2', to_string: 'High').current_status_matches 'High').to be false
      end
    end

    context 'old_status_matches' do
      it 'matches on id' do
        expect(change_item.old_status_matches 1).to be_truthy
      end

      it 'matches on String' do
        expect(change_item.old_status_matches 'To Do').to be_truthy
      end

      it 'matches on Status' do
        status = Status.new(
          name: 'In Progress', id: 1, category_name: 'one', category_id: 3, category_key: 'indeterminate'
        )
        expect(change_item.old_status_matches status).to be_truthy
      end

      it 'returns false when old value does not match' do
        expect(change_item.old_status_matches 'Done').to be false
      end

      it 'returns false when field is not status' do
        expect(change_for('priority', to: '1', to_string: 'High').old_status_matches 'To Do').to be false
      end
    end
  end
end
