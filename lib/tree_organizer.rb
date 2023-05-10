# frozen_string_literal: true

class TreeOrganizer
  attr_reader :cyclical_links

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

    def children?
      !@children.empty?
    end
  end

  def initialize issues:
    @issues = issues
    @root = Node.new
    @cyclical_links = []
    @node_hash = {}

    @issues.each do |issue|
      add issue
    end
  end

  def add issue, bread_crumbs = []
    parent_node = @root

    issue_node = find_node issue.key
    return issue_node if issue_node

    parent_issue = issue.parent
    if parent_issue
      cyclical = bread_crumbs.include? parent_issue.key
      bread_crumbs << issue.key
      if cyclical
        @cyclical_links << bread_crumbs.reverse
      else
        parent_node = find_node parent_issue.key
      end
      parent_node = add parent_issue, bread_crumbs if parent_node.nil?
    end

    issue_node = Node.new(issue: issue)
    if parent_node
      parent_node.children << issue_node
      @node_hash[issue_node.issue.key] = issue_node
    end
    issue_node
  end

  def find_node issue_key
    @node_hash[issue_key]
    # @root.children.find { |node| node.issue.key == issue_key }
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
