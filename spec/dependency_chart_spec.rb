# frozen_string_literal: true

require './spec/spec_helper'

describe DependencyChart do
  let(:subject) { DependencyChart.new nil }
  context 'build_dot_graph' do
    # Relationships: SP-15 is a clone of SP-13 and is blocked by SP-14
    let(:issue13) { load_issue('SP-13') }
    let(:issue14) { load_issue('SP-14') }
    let(:issue15) { load_issue('SP-15') }

    it 'should handle no issues' do
      subject.issues = []
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        '}'
      ]
    end

    it 'should handle simple graph of relationships with default configuration' do
      subject.issues = [issue13, issue14, issue15]
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="black"];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black"];),
        '}'
      ]
    end

    it 'should handle ignore for a link type' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link_name, rules|
        rules.ignore if link_name == 'Cloners'
      end
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        '}'
      ]
    end
  end
end
