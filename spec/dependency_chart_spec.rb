# frozen_string_literal: true

require './spec/spec_helper'

describe DependencyChart do
  let(:subject) { DependencyChart.new nil }
  let(:empty_issue_rules) { ->(_issue, rules) {} }

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
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
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
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
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
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
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
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="foo",color="black"];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="foo",color="black"];),
        '}'
      ]
    end

    it 'should support merge_bidirectional while keeping outward' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'outward' if link.name == 'Cloners'
      end
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        # "SP-13" -> "SP-15"[label="is cloned by",color="black"];) should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black"];),
        '}'
      ]
    end

    it 'should support merge_bidirectional while keeping inward' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'inward' if link.name == 'Cloners'
      end
      subject.issue_rules(&empty_issue_rules)
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="black"];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        # %("SP-15" -> "SP-13"[label="clones",color="black"];), should be removed
        '}'
      ]
    end

    it 'should merge_bidirectional when the data only goes one way' do
      # Remove the inward Cloner link for issue 15
      issue13.raw['fields']['issuelinks'].reject! do |link_json|
        link_json['type']['name'] == 'Cloners' && link_json['inwardIssue']
      end

      subject.issues = [issue13, issue14, issue15]
      subject.issue_rules(&empty_issue_rules)
      subject.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'inward' if link.name == 'Cloners'
      end
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        # %("SP-13" -> "SP-15"[label="is cloned by",color="black"];), # Should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black"];),
        '}'
      ]
    end

    it 'should support raise exception for invalid keep argument in merge_bidirectional' do
      subject.issues = [issue13, issue14, issue15]
      subject.issue_rules(&empty_issue_rules)
      subject.link_rules do |_link, rules|
        rules.merge_bidirectional keep: 'up'
      end
      expect { subject.build_dot_graph }.to raise_error 'Keep must be either inward or outward: up'
    end

    it 'should draw double arrowhead' do
      subject.issues = [issue13, issue14, issue15]
      subject.link_rules do |link, rules|
        rules.use_bidirectional_arrows if link.name == 'Cloners'
      end
      subject.issue_rules(&empty_issue_rules)
      # subject.build_dot_graph.each { |line| puts line }
      expect(subject.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="black",dir=both];),
        %("SP-14" -> "SP-15"[label="blocks",color="black"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="black"];),
        %("SP-15" -> "SP-13"[label="clones",color="black",dir=both];),
        '}'
      ]
    end
  end

  context 'make_dot_issue' do
    it 'should handle simple case' do
      rules = DependencyChart::IssueRules.new
      expect(subject.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end

    it 'should support color' do
      rules = DependencyChart::IssueRules.new
      rules.color = 'red'
      expect(subject.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event",style=filled,fillcolor="red"]))
      )
    end

    it 'should support plain label' do
      rules = DependencyChart::IssueRules.new
      rules.label = 'hello'
      expect(subject.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="hello",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end

    it 'should support html label' do
      rules = DependencyChart::IssueRules.new
      rules.label = '<hello>'
      expect(subject.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label=<hello>,shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end
  end

  context 'default_color_for_issue' do
    it 'should return colors for all normal issue types' do
      expect(subject.default_color_for_issue(issue13)).to be_truthy
    end
  end

  context 'shrink_svg' do
    it 'should shrink' do
      svg = '<svg width="914pt" height="1126pt" viewBox="0.00 0.00 914.00 1126.00"'
      expected = '<svg width="731pt" height="900pt" viewBox="0.00 0.00 914.00 1126.00"'
      expect(subject.shrink_svg svg).to eq expected
    end
  end
end
