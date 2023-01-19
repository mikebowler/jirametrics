# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkByParentChart do
  let(:issue1) { load_issue 'SP-1' }
  let(:issue2) { load_issue 'SP-2' }
  let(:epic1) { load_issue('SP-1').tap { |issue| issue.raw['key'] = 'EPIC-1' } }

  context 'group_hierarchy' do
    it 'should handle no issues' do
      subject = AgingWorkByParentChart.new
      expect(subject.group_hierarchy []).to be_empty
    end

    it 'should handle an issue with no parent' do
      subject = AgingWorkByParentChart.new
      expect(subject.group_hierarchy [issue1]).to eq([
        AgingWorkByParentChart::Row.new(issue: issue1, indent_level: 0, is_primary_issue: true)
      ])
    end

    xit 'should handle two top level issues' do
      subject = AgingWorkByParentChart.new
      expect(subject.group_hierarchy [issue1, issue2]).to eq([
        AgingWorkByParentChart::Row.new(issue: issue1, indent_level: 0, is_primary_issue: false),
        AgingWorkByParentChart::Row.new(issue: issue2, indent_level: 1, is_primary_issue: true)
      ])
    end

    xit 'should handle two top level issues' do
      subject = AgingWorkByParentChart.new
      issue1.parent = epic1
      expect(subject.group_hierarchy [issue1]).to eq([
        AgingWorkByParentChart::Row.new(issue: epic1, indent_level: 0, is_primary_issue: false),
        AgingWorkByParentChart::Row.new(issue: issue1, indent_level: 1, is_primary_issue: true)
      ])
    end
  end
end
