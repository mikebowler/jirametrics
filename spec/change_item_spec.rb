# frozen_string_literal: true

require './spec/spec_helper'

describe ChangeItem do
  it 'should create change' do
    time = Time.parse('2021-09-06T04:33:55.539+0000')
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
    time = Time.parse('2021-09-06T04:33:55.539+0000')
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
end
