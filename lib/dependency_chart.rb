# frozen_string_literal: true

require './lib/chart_base'
require 'open3'

class DependencyChart < ChartBase

  def run
    svg = execute_graphviz(build_dot_graph(find_links))
    "<h1>Dependencies</h1>#{svg}"
  end

  def find_links
    result = []
    issues.each do |issue|
      result += issue.issue_links
    end
    result.reject do |link|
      # TODO: These are configurable values so there needs to be a way to configure them here.
      ['Cloners', 'Issue split', 'Duplicate', 'Satisfy Requirement', 'Parent/Child'].include? link.name
    end
  end

  def build_dot_graph issue_links
    issue_keys = Set.new
    issue_links.each do |link|
      issue_keys << link.origin.key
      issue_keys << link.other_issue.key
    end

    dot_graph = String.new
    dot_graph << "digraph mygraph {\nrankdir=LR\n"
    issue_keys.each do |key|
      dot_graph << %("#{key}"[label="#{key}|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]\n)
    end

    issue_links.each do |link|
      dot_graph << %("#{link.origin.key}" -> "#{link.other_issue.key}"[ label="#{link.label}",color="black" ];\n)
    end

    dot_graph << '}'
    dot_graph
  end

  def execute_graphviz dot_graph
    Open3.popen3('dot -Tsvg') do |stdin, stdout, _stderr, _wait_thread|
      stdin.write dot_graph
      stdin.close
      return stdout.read
    end
  end
end

# name="Cloners", inward="is cloned by", outward="clones"
# name="To be done after", inward="To be done before", outward="To be done after"
# name="Relates", inward="relates to", outward="relates to"
# name="Blocks", inward="is blocked by", outward="blocks"
# name="Issue split", inward="split from", outward="split to"
# name="Duplicate", inward="is duplicated by", outward="duplicates"
# name="Problem/Incident", inward="is caused by", outward="causes"
# name="Depends", inward="Is Depended on by", outward="Depends on"
