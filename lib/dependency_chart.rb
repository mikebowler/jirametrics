# frozen_string_literal: true

require './lib/chart_base'
require 'open3'

class Rules
  def ignore
    @ignore = true
  end

  def ignored?
    @ignore
  end
end

class DependencyChart < ChartBase
  class LinkRules < Rules
    attr_accessor :line_color, :label

    def merge_bidirectional keep: 'inward'
      raise "Keep must be either inward or outward: #{keep}" unless %i[inward outward].include? keep.to_sym

      @merge_bidirectional = keep.to_sym
    end

    def get_merge_bidirectional # rubocop:disable Naming/AccessorMethodName
      @merge_bidirectional
    end

    def use_bidirectional_arrows
      @use_bidirectional_arrows = true
    end

    def bidirectional_arrows?
      @use_bidirectional_arrows
    end
  end

  class IssueRules < Rules
    attr_accessor :color, :show_tooltip
  end

  def initialize rules_block
    super()
    @rules_block = rules_block
    @link_rules_block = ->(link_name, link_rules) {}
    @issue_rules_block = ->(issue, issue_rules) { issue_rules.color = default_color_for_issue(issue) }
  end

  def run
    instance_eval(&@rules_block) if @rules_block

    svg = execute_graphviz(build_dot_graph.join("\n"))
    "<h1>Dependencies</h1>#{svg}"
  end

  def link_rules &block
    @link_rules_block = block
  end

  def issue_rules &block
    @issue_rules_block = block
  end

  def find_links
    result = []
    issues.each do |issue|
      result += issue.issue_links
    end
    result
  end

  def make_dot_link issue_link:, link_rules:
    result = String.new
    result << issue_link.origin.key.inspect
    result << ' -> '
    result << issue_link.other_issue.key.inspect
    result << '['
    result << 'label=' << (link_rules.label || issue_link.label).inspect
    result << ',color=' << (link_rules.line_color || 'black').inspect
    result << ',dir=both' if link_rules.bidirectional_arrows?
    result << '];'
    result
  end

  def make_dot_issue issue:, issue_rules:
    result = String.new
    result << issue.key.inspect
    result << '['
    result << "label=\"#{issue.key}|#{issue.type}\""
    result << ',shape=Mrecord'
    tooltip = "#{issue.key}: #{issue.summary}"
    result << ",tooltip=#{tooltip[0..80].inspect}" if issue_rules.show_tooltip
    result << %(,style=filled,fillcolor="#{issue_rules.color}") if issue_rules.color
    result << ']'
    result
  end

  def build_dot_graph
    issue_links = find_links

    visible_issues = {}
    link_graph = []
    links_to_ignore = []

    issue_links.each do |link|
      next if links_to_ignore.include? link

      link_rules = LinkRules.new
      @link_rules_block.call link, link_rules

      next if link_rules.ignored?

      if link_rules.get_merge_bidirectional
        opposite = issue_links.find do |l|
          l.name == link.name && l.origin.key == link.other_issue.key && l.other_issue.key == link.origin.key
        end
        if opposite
          if link_rules.get_merge_bidirectional.to_sym == link.direction
            # We keep this one and discard the opposite
            links_to_ignore << opposite
          else
            # We keep the opposite and discard this one
            next
          end
        end
      end

      link_graph << make_dot_link(issue_link: link, link_rules: link_rules)

      visible_issues[link.origin.key] = link.origin
      visible_issues[link.other_issue.key] = link.other_issue
    end

    dot_graph = []
    dot_graph << 'digraph mygraph {'
    dot_graph << 'rankdir=LR'

    # Sort the keys so they are proccessed in a deterministic order.
    visible_issues.values.sort_by(&:key_as_i).each do |issue|
      rules = IssueRules.new
      @issue_rules_block.call(issue, rules)
      dot_graph << make_dot_issue(issue: issue, issue_rules: rules)
    end

    dot_graph += link_graph
    dot_graph << '}'
    dot_graph
  end

  def execute_graphviz dot_graph
    Open3.popen3('dot -Tsvg') do |stdin, stdout, _stderr, _wait_thread|
      stdin.write dot_graph
      stdin.close
      return stdout.read
    end
  rescue # rubocop:disable Style/RescueStandardError
    message = "Unable to execute the command 'dot' which is part of graphviz. " \
      'Ensure that graphviz is installed and that dot is in your path.'
    puts message
    message
  end

  def default_color_for_issue issue
    {
      'Story' => '#90EE90',
      'Task' => '#87CEFA',
      'Bug' => '#ffdab9',
      'Defect' => '#ffdab9',
      'Epic' => '#fafad2'
    }[issue.type]
  end
end
