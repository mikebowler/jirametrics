# frozen_string_literal: true

require './spec/spec_helper'

describe TreeOrganizer do
  let(:issue1) { empty_issue key: 'SP-1', created: '2022-01-01' }
  let(:issue2) { empty_issue key: 'SP-2', created: '2022-01-01' }
  let(:issue3) { empty_issue key: 'SP-3', created: '2022-01-01' }

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

    it 'should handle two issues that have each other as parents' do
      issue1.parent = issue2
      issue2.parent = issue1

      subject = TreeOrganizer.new issues: [issue1]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-2', 1],
        ['SP-1', 2]
      ])
      expect(subject.cyclical_links).to eq [%w[SP-2 SP-1]]
    end

    it 'should handle an issue that has itself as parent' do
      issue1.parent = issue1

      subject = TreeOrganizer.new issues: [issue1]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-1', 1],
        ['SP-1', 2]
      ])
      expect(subject.cyclical_links).to eq [%w[SP-1 SP-1]]
    end

    it 'should handle a three issue cyclical chain' do
      issue1.parent = issue2
      issue2.parent = issue3
      issue3.parent = issue1

      subject = TreeOrganizer.new issues: [issue1]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-3', 1],
        ['SP-2', 2],
        ['SP-1', 3]
      ])
      expect(subject.cyclical_links).to eq [%w[SP-3 SP-2 SP-1]]
    end

    it 'should the same issue twice but not at the root' do
      issue1.parent
      issue2.parent = issue1
      issue3.parent = issue2
      issue3a = issue3.dup
      issue3a.parent = issue2

      subject = TreeOrganizer.new issues: [issue1, issue2, issue3, issue3a]
      expect(subject.flattened_issue_keys).to eq([
        ['SP-1', 1],
        ['SP-2', 2],
        ['SP-3', 3]
      ])
      expect(subject.cyclical_links).to be_empty
    end
  end
end
