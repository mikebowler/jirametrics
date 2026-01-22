# frozen_string_literal: true

require './spec/spec_helper'

describe ChangeItem do
  let(:time) { Time.parse('2021-09-06T04:33:55.539+0000') }

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

    expect(change.to_s).to eq 'ChangeItem(field: "Flagged", value: "Blocked", time: "2021-09-06 04:33:55 +0000")'
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
      'ChangeItem(field: "Flagged", value: "Blocked", time: "2021-09-06 04:33:55 +0000", artificial)'
    )
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
    end
  end
end
