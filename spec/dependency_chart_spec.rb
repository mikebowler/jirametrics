# frozen_string_literal: true

require './spec/spec_helper'

describe DependencyChart do
  let(:subject) { DependencyChart.new nil }

  # Relationships: SP-15 is a clone of SP-13 and is blocked by SP-14
  let(:issue13) { load_issue('SP-13') }
  let(:issue14) { load_issue('SP-14') }
  let(:issue15) { load_issue('SP-15') }

  context 'build_dot_graph' do
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
      subject.link_rules do |link, rules|
        rules.ignore if link.name == 'Cloners'
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

    it 'should handle line_color for links' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.line_color = 'blue' if link.name == 'Cloners'
      end
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="blue"];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="blue"];),
        '}'
      ]
    end

    it 'should support labels for links' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.label = 'foo' if link.name == 'Cloners'
      end
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-13" -> "SP-15"[label="foo",color="black"];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="foo",color="black"];),
        '}'
      ]
    end

    it 'should support merge_bidirectional' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'outward' if link.name == 'Cloners'
      end
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        # "SP-13" -> "SP-15"[label="is cloned by",color="black"];) should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black"];),
        '}'
      ]
    end

    it 'should draw double arrowhead' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.use_bidirectional_arrows if link.name == 'Cloners'
      end
      # subject.build_dot_graph.each { |line| puts line }
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="black",dir=both];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black",dir=both];),
        '}'
      ]
    end
  end
end
