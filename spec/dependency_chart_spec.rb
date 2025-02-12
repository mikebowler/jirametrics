# frozen_string_literal: true

require './spec/spec_helper'

describe DependencyChart do
  let(:chart) { described_class.new nil }
  let(:empty_issue_rules) { ->(_issue, rules) { rules.color = :none } }

  # Relationships: SP-15 is a clone of SP-13 and is blocked by SP-14
  let(:issue13) { load_issue('SP-13') }
  let(:issue14) { load_issue('SP-14') }
  let(:issue15) { load_issue('SP-15') }

  context 'build_dot_graph' do
    it 'handles no issues' do
      chart.issues = []
      expect(chart.build_dot_graph).to be_nil
    end

    it 'handles simple graph of relationships with default configuration' do
      # Cloner should be excluded and the bi-directional block should become one.
      chart.issues = [issue13, issue14, issue15]
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        '}'
      ]
    end

    it 'handles ignore for a link type' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.ignore if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        '}'
      ]
    end

    it 'handles line_color for links' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.line_color = 'blue' if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="blue",fontcolor="blue"];),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-13"[label="clones",color="blue",fontcolor="blue"];),
        '}'
      ]
    end

    it 'supports labels for links' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.label = 'foo' if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="foo",color="gray",fontcolor="gray"];),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-13"[label="foo",color="gray",fontcolor="gray"];),
        '}'
      ]
    end

    it 'supports merge_bidirectional while keeping outward' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'outward' if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        # "SP-13" -> "SP-15"[label="is cloned by",color="gray",fontcolor="gray"];) should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-13"[label="clones",color="gray",fontcolor="gray"];),
        '}'
      ]
    end

    it 'supports merge_bidirectional while keeping inward' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'inward' if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="gray",fontcolor="gray"];),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        # %("SP-15" -> "SP-13"[label="clones",color="gray",fontcolor="gray"];), should be removed
        '}'
      ]
    end

    it 'supports merge_bidirectional when the data only goes one way' do
      # Remove the inward Cloner link for issue 15
      issue13.raw['fields']['issuelinks'].reject! do |link_json|
        link_json['type']['name'] == 'Cloners' && link_json['inwardIssue']
      end

      chart.issues = [issue13, issue14, issue15]
      chart.issue_rules(&empty_issue_rules)
      chart.link_rules do |link, rules|
        rules.merge_bidirectional keep: 'inward' if link.name == 'Cloners'
      end
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        # %("SP-13" -> "SP-15"[label="is cloned by",color="gray,fontcolor="gray""];), # Should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-13"[label="clones",color="gray",fontcolor="gray"];),
        '}'
      ]
    end

    it 'supports raise exception for invalid keep argument in merge_bidirectional' do
      chart.issues = [issue13, issue14, issue15]
      chart.issue_rules(&empty_issue_rules)
      chart.link_rules do |_link, rules|
        rules.merge_bidirectional keep: 'up'
      end
      expect { chart.build_dot_graph }.to raise_error 'Keep must be either inward or outward: up'
    end

    it 'draws double arrowhead' do
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.use_bidirectional_arrows if link.name == 'Cloners'
      end
      chart.issue_rules(&empty_issue_rules)
      expect(chart.build_dot_graph).to eq [
        'digraph mygraph {',
        'rankdir=LR',
        'bgcolor="transparent"',
        %("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]),
        %("SP-14"[label="SP-14|Story",shape=Mrecord,tooltip="SP-14: Save credit card information"]),
        %("SP-15"[label="SP-15|Story",shape=Mrecord,tooltip="SP-15: CLONE - Report of people checked in at an event"]),
        %("SP-13" -> "SP-15"[label="is cloned by",color="gray",fontcolor="gray",dir=both];),
        %("SP-14" -> "SP-15"[label="blocks",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="gray",fontcolor="gray"];),
        %("SP-15" -> "SP-13"[label="clones",color="gray",fontcolor="gray",dir=both];),
        '}'
      ]
    end
  end

  context 'make_dot_issue' do
    it 'handles simple case' do
      rules = DependencyChart::IssueRules.new
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end

    it 'supports color' do
      rules = DependencyChart::IssueRules.new
      rules.color = 'red'
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,style=filled,fillcolor="red"]))
      )
    end

    it 'supports plain label' do
      rules = DependencyChart::IssueRules.new
      rules.label = 'hello'
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="hello",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end

    it 'supports html label' do
      rules = DependencyChart::IssueRules.new
      rules.label = '<hello>'
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label=<hello>,shape=Mrecord,tooltip="SP-13: Report of people checked in at an event"]))
      )
    end
  end

  context 'shrink_svg' do
    it 'shrinks' do
      svg = '<svg width="914pt" height="1126pt" viewBox="0.00 0.00 914.00 1126.00"'
      expected = '<svg width="731pt" height="900pt" viewBox="0.00 0.00 914.00 1126.00"'
      expect(chart.shrink_svg svg).to eq expected
    end
  end

  context 'word_wrap' do
    it 'handles different line endings coming in' do
      expect(chart.word_wrap "a\nb\r\nc", max_width: 80, separator: '|').to eq 'a|b|c'
    end

    it 'handles empty string' do
      expect(chart.word_wrap '', max_width: 80, separator: '|').to eq ''
    end

    it 'handles simple too long string' do
      expect(chart.word_wrap 'this is a long string', max_width: 10, separator: "\n").to eq(
        "this is a\nlong\nstring"
      )
    end

    it 'handles text that cannnot be wrapped' do
      expect(chart.word_wrap 'this is a absolutelyhorriblylong string', max_width: 10, separator: "\n").to eq(
        "this is a\nabsolutelyhorriblylong\nstring"
      )
    end
  end

  context 'default_issue_rules' do
    it 'handles done' do
      rules = DependencyChart::IssueRules.new
      issue13.board.cycletime = mock_cycletime_config stub_values: [
        [issue13, '2024-01-01', '2024-01-02']
      ]
      chart.default_issue_rules.call issue13, rules
      expect(rules.label).to eq '<<S>SP-13 </S>  [Story]<BR/>Done<BR/>Report of people checked in at an event>'
    end

    it 'Handles in progress' do
      rules = DependencyChart::IssueRules.new
      issue13.board.cycletime = mock_cycletime_config stub_values: [
        [issue13, '2024-01-01', nil]
      ]
      chart.date_range = to_date('2024-01-01')..to_date('2024-01-05')
      chart.default_issue_rules.call issue13, rules
      expect(rules.label).to eq '<SP-13 [Story]<BR/>Age: 5 days<BR/>Report of people checked in at an event>'
    end

    it 'handles in not started' do
      rules = DependencyChart::IssueRules.new
      issue13.board.cycletime = mock_cycletime_config stub_values: [
        [issue13, nil, nil]
      ]
      chart.default_issue_rules.call issue13, rules
      expect(rules.label).to eq '<SP-13 [Story]<BR/>Not started<BR/>Report of people checked in at an event>'
    end

    it 'handles artificial issue' do
      rules = DependencyChart::IssueRules.new
      issue13.raw['exporter'] = nil
      issue13.board.cycletime = mock_cycletime_config stub_values: [
        [issue13, nil, nil]
      ]
      chart.default_issue_rules.call issue13, rules
      expect(rules.label).to eq(
        '<<S>SP-13 </S>  [Story]<BR/>(unknown state)<BR/>Report of people checked in at an event>'
      )
    end
  end
end
