# frozen_string_literal: true

require './spec/spec_helper'

describe TreeOrganizer do
  let(:issue1) { empty_issue key: 'SP-1', created: '2022-01-01' }
  let(:issue2) { empty_issue key: 'SP-2', created: '2022-01-01' }

  context 'Adding issues' do
    it 'should handle no issues' do
      subject = TreeOrganizer.new issues: []
      expect(subject.flattened_issue_keys).to be_empty
    end

    it 'should handle single issue' do
      subject = TreeOrganizer.new issues: [issue1]
      expect(subject.flattened_issue_keys).to eq([['SP-1', 1]])
    end

    it 'should handle single issue with a parent' do
      issue1.parent = issue2
      subject = TreeOrganizer.new issues: [issue1]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-2', 1],
        ['SP-1', 2]
      ])
    end

    it 'should handle two different issues with the same parent' do
      issue1.parent = empty_issue key: 'SP-10', created: '2022-01-01'
      issue2.parent = empty_issue key: 'SP-10', created: '2022-01-02'

      subject = TreeOrganizer.new issues: [issue2, issue1]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-10', 1],
        ['SP-1', 2],
        ['SP-2', 2]
      ])
    end
  end

end
