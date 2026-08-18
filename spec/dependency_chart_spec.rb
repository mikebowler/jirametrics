# frozen_string_literal: true

require './spec/spec_helper'

describe DependencyChart do
  let(:chart) { described_class.new nil }
  let(:empty_issue_rules) { ->(_issue, rules) { rules.color = :none } }

  # Relationships: SP-15 is a clone of SP-13 and is blocked by SP-14
  let(:issue13) { load_issue('SP-13') }
  let(:issue14) { load_issue('SP-14') }
  let(:issue15) { load_issue('SP-15') }

  describe '#build_dot_graph' do
    # These tests all suppress the fill, so every label is the theme text colour. It is the second
    # placeholder rather than the first because the links are built before the nodes.
    def unfilled_node key, summary
      %("#{key}"[label="#{key}|Story",shape=Mrecord,tooltip="#{key}: #{summary}",fontcolor="#fe0002"])
    end

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
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-13" -> "SP-15"[label="is cloned by",color="blue",fontcolor="blue"];),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-13" -> "SP-15"[label="foo",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-13"[label="foo",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        # "SP-13" -> "SP-15"[label="is cloned by",color="#fe0001",fontcolor="#fe0001"];) should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-13"[label="clones",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-13" -> "SP-15"[label="is cloned by",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
        # %("SP-15" -> "SP-13"[label="clones",color="#fe0001",fontcolor="#fe0001"];), should be removed
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        # %("SP-13" -> "SP-15"[label="is cloned by",color="gray,fontcolor="gray""];), # Should be removed
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-13"[label="clones",color="#fe0001",fontcolor="#fe0001"];),
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
        unfilled_node('SP-13', 'Report of people checked in at an event'),
        unfilled_node('SP-14', 'Save credit card information'),
        unfilled_node('SP-15', 'CLONE - Report of people checked in at an event'),
        %("SP-13" -> "SP-15"[label="is cloned by",color="#fe0001",fontcolor="#fe0001",dir=both];),
        %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];),
        %("SP-15" -> "SP-13"[label="clones",color="#fe0001",fontcolor="#fe0001",dir=both];),
        '}'
      ]
    end

    it 'passes each visible issue to the issue_rules block' do
      chart.issues = [issue13, issue14, issue15]
      seen_keys = []
      chart.issue_rules do |issue, rules|
        seen_keys << issue.key
        rules.color = :none
      end
      chart.build_dot_graph
      expect(seen_keys).to include('SP-14', 'SP-15')
    end

    it 'skips the opposite via links_to_ignore but keeps processing later links' do
      # Only the outward links merge, so each inward link would survive on its own merits - the only
      # thing suppressing the inward Blocks link is links_to_ignore, populated when its outward partner
      # is kept. A visible Cloners link follows it in the list, so the loop must carry on past the
      # skipped one (next) rather than stopping (break).
      chart.issues = [issue13, issue14, issue15]
      chart.link_rules do |link, rules|
        rules.merge_bidirectional(keep: 'outward') if link.direction == :outward
      end
      chart.issue_rules(&empty_issue_rules)
      graph = chart.build_dot_graph
      aggregate_failures do
        expect(graph).to include %("SP-14" -> "SP-15"[label="blocks",color="#fe0001",fontcolor="#fe0001"];)
        expect(graph).not_to include %("SP-15" -> "SP-14"[label="is blocked by",color="#fe0001",fontcolor="#fe0001"];)
        expect(graph).to include %("SP-15" -> "SP-13"[label="clones",color="#fe0001",fontcolor="#fe0001"];)
      end
    end
  end

  describe '#find_opposite_link' do
    def link name:, origin:, other:
      double(name: name, origin: double(key: origin), other_issue: double(key: other))
    end

    it 'finds the reverse link with the same name, ignoring near-misses' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2')
      opposite = link(name: 'Blocks', origin: 'SP-2', other: 'SP-1')
      candidates = [
        link(name: 'Clones', origin: 'SP-2', other: 'SP-1'), # wrong name
        link(name: 'Blocks', origin: 'SP-2', other: 'SP-3'), # right origin, wrong other
        link(name: 'Blocks', origin: 'SP-3', other: 'SP-1'), # wrong origin, right other
        opposite
      ]
      expect(chart.find_opposite_link(target, candidates)).to be opposite
    end

    it 'returns nil when there is no opposite' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2')
      expect(chart.find_opposite_link(target, [link(name: 'Blocks', origin: 'SP-2', other: 'SP-3')])).to be_nil
    end
  end

  describe '#merge_bidirectional_skip?' do
    def link name:, origin:, other:, direction:
      double(name: name, origin: double(key: origin), other_issue: double(key: other), direction: direction)
    end

    def link_rules merge
      double(get_merge_bidirectional: merge)
    end

    it 'keeps the link when no merge is configured, even if an opposite exists' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2', direction: :outward)
      opposite = link(name: 'Blocks', origin: 'SP-2', other: 'SP-1', direction: :inward)
      ignore = []
      expect(chart.merge_bidirectional_skip?(target, link_rules(nil), [target, opposite], ignore)).to be false
      expect(ignore).to be_empty
    end

    it 'keeps the link and ignores nothing when there is no matching opposite' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2', direction: :outward)
      ignore = []
      expect(chart.merge_bidirectional_skip?(target, link_rules('outward'), [target], ignore)).to be false
      expect(ignore).to be_empty
    end

    it 'keeps this link and ignores the opposite when the direction matches' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2', direction: :outward)
      opposite = link(name: 'Blocks', origin: 'SP-2', other: 'SP-1', direction: :inward)
      ignore = []
      result = chart.merge_bidirectional_skip?(target, link_rules('outward'), [target, opposite], ignore)
      aggregate_failures do
        expect(result).to be false
        expect(ignore).to eq [opposite]
      end
    end

    it 'skips this link when the direction does not match' do
      target = link(name: 'Blocks', origin: 'SP-1', other: 'SP-2', direction: :inward)
      opposite = link(name: 'Blocks', origin: 'SP-2', other: 'SP-1', direction: :outward)
      ignore = []
      result = chart.merge_bidirectional_skip?(target, link_rules('outward'), [target, opposite], ignore)
      aggregate_failures do
        expect(result).to be true
        expect(ignore).to be_empty
      end
    end
  end

  describe '#run' do
    let(:rendered_svg) { %(<svg width="10pt" height="5pt">body</svg>) }

    before do
      chart.issues = [issue13, issue14, issue15]
      chart.time_range = to_time('2021-06-01')..to_time('2021-12-01')
    end

    # Graphviz has no idea what a CSS variable is. Handed one it silently draws black, which is
    # how the chart ended up as black text on a black background.
    it 'never puts a css variable in the graph it hands to graphviz' do
      # A type with no colour of its own falls back to the palette, which deals in CSS variables.
      chart.issue_rules { |_issue, rules| rules.color = chart.color_for(type: 'Sub-task') }
      dot_graph = nil
      allow(chart).to receive(:execute_graphviz) do |dot|
        dot_graph = dot
        rendered_svg
      end
      chart.run
      expect(dot_graph).not_to include 'var('
    end

    it 'maps the placeholders back to variables in the rendered svg' do
      chart.issue_rules { |_issue, rules| rules.color = CssVariable['--palette-color-1'] }
      allow(chart).to receive(:execute_graphviz).and_return(rendered_svg)
      html = chart.run
      placeholder = chart.css_variable_placeholders.fetch '--palette-color-1'
      fill_rule = %([fill="#{placeholder}"]{fill:var(--palette-color-1)})
      stroke_rule = %([stroke="#{placeholder}"]{stroke:var(--palette-color-1)})
      expect(html).to include %(#{fill_rule}#{stroke_rule})
    end
  end

  describe '#make_dot_link' do
    # Link lines and their labels sit on the page rather than inside a node, so gray had to go:
    # it was down to about 2.4:1 against the dark theme background.
    it 'defaults the line colour to an overridable variable' do
      rules = DependencyChart::LinkRules.new
      target = instance_double(IssueLink, label: 'blocks', origin: double(key: 'SP-1'),
        other_issue: double(key: 'SP-2'))
      chart.make_dot_link issue_link: target, link_rules: rules
      expect(chart.css_variable_placeholders).to eq({ '--dependency-chart-link-color' => '#fe0001' })
    end

    it 'substitutes a placeholder when the line colour is a CSS variable' do
      rules = DependencyChart::LinkRules.new
      rules.line_color = CssVariable['--palette-color-1']
      target = instance_double(IssueLink, label: 'blocks', origin: double(key: 'SP-1'),
        other_issue: double(key: 'SP-2'))
      expect(chart.make_dot_link issue_link: target, link_rules: rules).to(
        eq(%("SP-1" -> "SP-2"[label="blocks",color="#fe0001",fontcolor="#fe0001"];))
      )
    end
  end

  describe '#make_dot_issue' do
    it 'handles simple case' do
      rules = DependencyChart::IssueRules.new
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,fontcolor="#fe0001"]))
      )
    end

    it 'supports color' do
      rules = DependencyChart::IssueRules.new
      rules.color = 'red'
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,style=filled,fillcolor="red",fontcolor="#fe0001"]))
      )
    end

    # A filled node is its own background so the label is measured against the fill, while an
    # unfilled one sits on the page and has to follow the theme instead.
    it 'labels a filled node with the dependency chart label colour' do
      rules = DependencyChart::IssueRules.new
      rules.color = 'red'
      chart.make_dot_issue issue: issue13, issue_rules: rules
      expect(chart.css_variable_placeholders).to eq({ '--dependency-chart-label-color' => '#fe0001' })
    end

    it 'labels an unfilled node with the theme text colour' do
      rules = DependencyChart::IssueRules.new
      rules.color = :none
      chart.make_dot_issue issue: issue13, issue_rules: rules
      expect(chart.css_variable_placeholders).to eq({ '--default-text-color' => '#fe0001' })
    end

    it 'substitutes a placeholder when the colour is a CSS variable' do
      rules = DependencyChart::IssueRules.new
      rules.color = CssVariable['--palette-color-1']
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="SP-13|Story",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,style=filled,fillcolor="#fe0001",fontcolor="#fe0002"]))
      )
    end

    it 'supports plain label' do
      rules = DependencyChart::IssueRules.new
      rules.label = 'hello'
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label="hello",shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,fontcolor="#fe0001"]))
      )
    end

    it 'supports html label' do
      rules = DependencyChart::IssueRules.new
      rules.label = '<hello>'
      rules.color = :none
      expect(chart.make_dot_issue issue: issue13, issue_rules: rules).to(
        eq(%("SP-13"[label=<hello>,shape=Mrecord,tooltip="SP-13: Report of people checked in at an event") +
          %(,fontcolor="#fe0001"]))
      )
    end
  end

  describe '#color_for' do
    it 'gives a type it knows about its own overridable variable' do
      expect(chart.color_for type: 'Story').to eq CssVariable['--dependency-chart-story-color']
    end

    it 'gives Defect the same colour as Bug' do
      expect(chart.color_for type: 'Defect').to eq(chart.color_for type: 'Bug')
    end

    it 'gives the same unknown type the same colour every time' do
      first_call = chart.color_for type: 'Sub-task'
      expect(chart.color_for type: 'Sub-task').to eq first_call
    end

    it 'gives two unknown types different colours' do
      expect(chart.color_for type: 'Sub-task').not_to eq(chart.color_for type: 'Incident')
    end
  end

  describe 'the CSS variables it names' do
    # A name the stylesheet does not define resolves to nothing rather than raising, so the colour
    # would quietly vanish and nobody would find out until a chart looked wrong. That is precisely
    # how the black-on-black bug survived, so the two sides are tied together here.
    it 'are all defined in index.css' do
      css = File.read 'lib/jirametrics/html/index.css'
      used = %w[Story Task Bug Defect Epic Spike].collect { |type| chart.color_for type: type }
      used << chart.label_color(filled: true) << chart.label_color(filled: false) << chart.default_link_color
      undefined = used.uniq.collect(&:name).reject { |name| css.match?(/^\s*#{Regexp.escape name}:/) }
      expect(undefined).to be_empty
    end
  end

  describe '#graphviz_color' do
    it 'passes a literal colour through untouched' do
      expect(chart.graphviz_color('red')).to eq 'red'
    end

    it 'substitutes a placeholder for a CSS variable, which graphviz cannot parse' do
      expect(chart.graphviz_color(CssVariable['--palette-color-1'])).to eq '#fe0001'
    end

    it 'gives the same variable the same placeholder and a different one its own' do
      first = chart.graphviz_color(CssVariable['--palette-color-1'])
      second = chart.graphviz_color(CssVariable['--palette-color-2'])
      aggregate_failures do
        expect(chart.graphviz_color(CssVariable['--palette-color-1'])).to eq first
        expect(second).not_to eq first
      end
    end
  end

  describe '#restore_css_variables' do
    it 'leaves the svg alone when no colour was a variable' do
      svg = %(<svg width="10pt"><path fill="black"/></svg>)
      expect(chart.restore_css_variables svg).to eq svg
    end

    it 'maps each placeholder back to its variable, for both fill and stroke' do
      chart.graphviz_color CssVariable['--palette-color-1']
      fill_rule = %([fill="#fe0001"]{fill:var(--palette-color-1)})
      stroke_rule = %([stroke="#fe0001"]{stroke:var(--palette-color-1)})
      expect(chart.restore_css_variables %(<svg width="10pt">body</svg>)).to eq(
        %(<svg width="10pt"><style>#{fill_rule}#{stroke_rule}</style>body</svg>)
      )
    end

    it 'handles the multi-line opening tag that graphviz actually emits' do
      chart.graphviz_color CssVariable['--palette-color-1']
      svg = %(<svg width="10pt" height="5pt"\n viewBox="0 0 10 5" xmlns="http://www.w3.org/2000/svg">body</svg>)
      expect(chart.restore_css_variables(svg)).to include %(xmlns="http://www.w3.org/2000/svg"><style>)
    end
  end

  describe '#shrink_svg' do
    it 'shrinks' do
      svg = '<svg width="914pt" height="1126pt" viewBox="0.00 0.00 914.00 1126.00"'
      expected = '<svg width="731pt" height="900pt" viewBox="0.00 0.00 914.00 1126.00"'
      expect(chart.shrink_svg svg).to eq expected
    end
  end

  describe '#word_wrap' do
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

  describe '#default_issue_rules' do
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
