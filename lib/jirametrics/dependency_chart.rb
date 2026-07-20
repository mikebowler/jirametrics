# frozen_string_literal: true

require 'jirametrics/chart_base'
require 'open3'
require 'jirametrics/rules'

class DependencyChart < ChartBase
  class LinkRules < Rules
    attr_accessor :line_color, :label

    def merge_bidirectional keep: 'inward'
      raise "Keep must be either inward or outward: #{keep}" unless %i[inward outward].include? keep.to_sym

      @merge_bidirectional = keep.to_sym
    end

    # get_ prefix because the plain name is the config DSL setter (merge_bidirectional keep:).
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
    attr_accessor :color, :label
  end

  def initialize rules_block
    super()

    header_text 'Dependencies'
    description_text <<-HTML
      <p>
        These are all the "linked issues" as defined in Jira
      </p>
    HTML

    @rules_block = rules_block

    issue_rules(&default_issue_rules)
    link_rules(&default_link_rules)
  end

  def run
    instance_eval(&@rules_block) if @rules_block

    dot_graph = build_dot_graph
    if dot_graph.nil?
      return "<h1 class='foldable'>#{@header_text}</h1>" \
        '<div>No data matched the selected criteria. Nothing to show.</div>'
    end

    svg = execute_graphviz(dot_graph.join("\n"))
    "<h1 class='foldable'>#{@header_text}</h1><div>#{@description_text}#{shrink_svg svg}</div>"
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
    result = +''
    result << issue_link.origin.key.inspect
    result << ' -> '
    result << issue_link.other_issue.key.inspect
    result << '['
    result << 'label=' << (link_rules.label || issue_link.label).inspect
    result << ',color=' << (link_rules.line_color || 'gray').inspect
    result << ',fontcolor=' << (link_rules.line_color || 'gray').inspect
    result << ',dir=both' if link_rules.bidirectional_arrows?
    result << '];'
    result
  end

  def make_dot_issue issue:, issue_rules:
    result = +''
    result << issue.key.inspect
    result << '['
    label = issue_rules.label || "#{issue.key}|#{issue.type}"
    label = label.inspect unless label.match?(/^<.+>$/)
    result << "label=#{label}"
    result << ',shape=Mrecord'
    tooltip = "#{issue.key}: #{issue.summary}"
    result << ",tooltip=#{tooltip[0..80].inspect}"
    unless issue_rules.color == :none
      result << %(,style=filled,fillcolor="#{issue_rules.color || color_for(type: issue.type)}")
    end
    result << ']'
    result
  end

  # This used to pull colours from chart_base but the migration to CSS colours kept breaking
  # this chart so we moved it here, until we're finished with the rest. TODO: Revisit whether
  # this can also use customizable CSS colours
  def color_for type:
    @chart_colors = {
      'Story' => '#90EE90',
      'Task' => '#87CEFA',
      'Bug' => '#ffdab9',
      'Defect' => '#ffdab9',
      'Epic' => '#fafad2',
      'Spike' => '#DDA0DD' # light purple
    }[type] ||= random_color
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
      next if merge_bidirectional_skip?(link, link_rules, issue_links, links_to_ignore)

      link_graph << make_dot_link(issue_link: link, link_rules: link_rules)
      visible_issues[link.origin.key] = link.origin
      visible_issues[link.other_issue.key] = link.other_issue
    end

    return nil if visible_issues.empty?

    assemble_dot_graph(visible_issues, link_graph)
  end

  # For a bidirectional-merge link, collapses the pair into one. When this link is the one to keep, its
  # opposite is added to links_to_ignore; returns true when this link should be skipped in favour of its
  # opposite. Returns false (keep this link) when there's no merge or no matching opposite.
  def merge_bidirectional_skip? link, link_rules, issue_links, links_to_ignore
    merge_direction = link_rules.get_merge_bidirectional
    return false unless merge_direction

    opposite = find_opposite_link(link, issue_links)
    return false unless opposite

    if merge_direction.to_sym == link.direction
      links_to_ignore << opposite # keep this one, discard the opposite
      false
    else
      true # keep the opposite, skip this one
    end
  end

  def find_opposite_link link, issue_links
    issue_links.find do |candidate|
      candidate.name == link.name &&
        candidate.origin.key == link.other_issue.key &&
        candidate.other_issue.key == link.origin.key
    end
  end

  def assemble_dot_graph visible_issues, link_graph
    dot_graph = ['digraph mygraph {', 'rankdir=LR', 'bgcolor="transparent"']

    # Sort the keys so they are proccessed in a deterministic order.
    visible_issues.values.sort_by(&:key_as_i).each do |issue|
      rules = IssueRules.new
      @issue_rules_block.call(issue, rules)
      dot_graph << make_dot_issue(issue: issue, issue_rules: rules)
    end

    dot_graph + link_graph + ['}']
  end

  def execute_graphviz dot_graph
    Open3.popen3('dot -Tsvg') do |stdin, stdout, _stderr, _wait_thread|
      stdin.write dot_graph
      stdin.close
      return stdout.read
    end
  rescue # rubocop:disable Style/RescueStandardError
    message = 'Unable to generate the dependency chart because graphviz could not be found in the path.'
    file_system.log message, also_write_to_stderr: true
    message
  end

  def shrink_svg svg
    scale = 0.8
    svg.sub(/width="([\d.]+)pt" height="([\d.]+)pt"/) do
      width = $1.to_i * scale
      height = $2.to_i * scale
      "width=\"#{width.to_i}pt\" height=\"#{height.to_i}pt\""
    end
  end

  def word_wrap text, max_width: 50, separator: '<BR/>'
    text.chomp.lines.collect do |line|
      line.chomp!

      # The following characters all cause problems when passed to graphviz
      line.gsub!(/[{<]/, '[')
      line.gsub!(/[}>]/, ']')
      line.gsub!(/\s*&\s*/, ' and ')
      line.delete!('|')

      if line.length > max_width
        line.gsub(/(.{1,#{max_width}})(\s+|$)/, "\\1#{separator}").strip
      else
        line
      end
    end.join(separator)
  end

  def default_issue_rules
    chart = self
    lambda do |issue, rules|
      is_done = issue.done?

      key = issue.key
      key = "<S>#{key} </S> " if is_done
      line2 = +'<BR/>'
      if issue.artificial?
        line2 << '(unknown state)' # Shouldn't happen if we've done a full download but is still possible.
      elsif is_done
        line2 << 'Done'
      else
        started_at = issue.started_stopped_times.first
        if started_at.nil?
          line2 << 'Not started'
        else
          line2 << "Age: #{issue.board.cycletime.age(issue, today: chart.date_range.end)} days"
        end
      end
      rules.label = "<#{key} [#{issue.type}]#{line2}<BR/>#{word_wrap issue.summary}>"
    end
  end

  def default_link_rules
    lambda do |link, rules|
      rules.ignore if link.origin.done? && link.other_issue.done?
      rules.ignore if link.name == 'Cloners'
      rules.merge_bidirectional keep: 'outward'
    end
  end
end
