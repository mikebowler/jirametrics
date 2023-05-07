# frozen_string_literal: true

class TreeOrganizer
  class Node
    attr_accessor :parent, :issue
    attr_reader :children

    def initialize issue: nil
      @issue = issue
      @children = []
    end

    def to_s
      "Node(#{@issue&.key || 'Root'}, parent: #{@parent&.issue&.key || 'Root'}, children: #{@children.inspect})"
    end

    def inspect
      to_s
    end

    def <=> other
      issue <=> other.issue
    end

    def has_children?
      !@children.empty?
    end
  end

  def initialize issues:
    @issues = issues
    @root = Node.new

    @issues.each do |issue|
      add issue
    end
  end

  def add issue
    parent_node = @root

    parent_issue = issue.parent
    if parent_issue
      parent_node = find_node parent_issue.key
      parent_node = add parent_issue if parent_node.nil?
    end

    issue_node = Node.new(issue: issue)
    parent_node.children << issue_node
    issue_node
  end

  def find_node issue_key
    @root.children.find { |node| node.issue.key == issue_key }
  end

  def find_issue issue_key
    @issues.find { |issue| issue.key == issue_key }
  end

  def flattened_issue_keys
    flattened_nodes.collect do |node, depth|
      [node.issue.key, depth]
    end
  end

  def flattened_nodes
    list = []
    walk_children parent: @root, list: list, depth: 1
    list
  end

  def walk_children parent:, list:, depth:
    parent.children.sort.each do |node|
      list << [node, depth]
      walk_children parent: node, list: list, depth: depth + 1
    end
  end
end
