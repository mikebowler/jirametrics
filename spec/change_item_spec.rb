# frozen_string_literal: true

require './spec/spec_helper'

describe ChangeItem do
  let(:time) { Time.parse('2021-09-06T04:33:55.539+0000') }

  it 'should create change' do
    change = ChangeItem.new time: time, author: 'Tolkien', raw: {
      'field' => 'Flagged',
      'fieldtype' => 'custom',
      'fieldId' => 'customfield_10021',
      'from' => nil,
      'fromString' => nil,
      'to' => '[10019]',
      'toString' => 'Blocked'
    }

    expect(change.flagged?).to be_truthy
    expect(change.field).to eq 'Flagged'
    expect(change.value).to eq 'Blocked'
    expect(change.status?).to be_falsey
    expect(change.priority?).to be_falsey
    expect(change.resolution?).to be_falsey
    expect(change.artificial?).to be_falsey

    expect(change.to_s).to eq 'ChangeItem(field: "Flagged", value: "Blocked", time: "2021-09-06 04:33:55 +0000")'
  end

  it 'should support artificial' do
    change = ChangeItem.new time: time, artificial: true, author: 'Asimov', raw: {
      'field' => 'Flagged',
      'fieldtype' => 'custom',
      'fieldId' => 'customfield_10021',
      'from' => nil,
      'fromString' => nil,
      'to' => '[10019]',
      'toString' => 'Blocked'
    }

    expect(change.artificial?).to be_truthy
    expect(change.to_s).to eq(
      'ChangeItem(field: "Flagged", value: "Blocked", time: "2021-09-06 04:33:55 +0000", artificial)'
    )
  end

  context 'status_matches' do
    let(:subject) do
      ChangeItem.new time: time, author: 'Asimov', raw: {
        'field' => 'status',
        'from' => 1,
        'fromString' => 'To Do',
        'to' => 2,
        'toString' => 'In Progress'
      }
    end

    context 'current_status_matches' do
      it 'should match on id' do
        expect(subject.current_status_matches 2).to be_truthy
      end

      it 'should match on String' do
        expect(subject.current_status_matches 'In Progress').to be_truthy
      end

      it 'should match on Status' do
        status = Status.new name: 'In Progress', id: 2, category_name: 'one', category_id: 3
        expect(subject.current_status_matches status).to be_truthy
      end
    end

    context 'old_status_matches' do
      it 'should match on id' do
        expect(subject.old_status_matches 1).to be_truthy
      end

      it 'should match on String' do
        expect(subject.old_status_matches 'To Do').to be_truthy
      end

      it 'should match on Status' do
        status = Status.new name: 'In Progress', id: 1, category_name: 'one', category_id: 3
        expect(subject.old_status_matches status).to be_truthy
      end
    end
  end
end
