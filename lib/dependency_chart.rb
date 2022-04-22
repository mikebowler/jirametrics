# frozen_string_literal: true

require './lib/chart_base'

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
    result
  end

  def build_dot_graph issue_links
    issue_keys = Set.new
    issue_links.each do |link|
      issue_keys << link.to.key
      issue_keys << link.from.key
    end

    dot_graph = String.new
    dot_graph << "digraph mygraph {\nrankdir=LR\n"
    issue_keys.each do |key|
      dot_graph << %Q("#{key}"[label="#{key}|Story",shape=Mrecord,style=filled,fillcolor="#FFCCFF"]\n)
    end

    issue_links.each do |link|
      dot_graph << %Q("#{link.from.key}" -> "#{link.to.key}"[ label="#{link.label}",color="black" ];\n)
    end

    dot_graph << '}'
    dot_graph
  end

  def execute_graphviz dot_graph
    puts 'graphfiz'
    require 'open3'
    Open3.popen3('dot -Tsvg') do |stdin, stdout, _stderr, _wait_thread|
      stdin.write dot_graph
      stdin.close
      return stdout.read
    end
  end
end
