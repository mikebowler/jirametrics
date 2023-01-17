# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkByParentChart < ChartBase
  Row = Struct.new(:issue, :indent_level, :is_primary_issue, :started, :stopped, keyword_init: true) do
    def primary_issue? = @is_primary_issue
  end

  def initialize
    super()

    header_text 'Aging Work By Parent'
    description_text <<-HTML
      <p>
        This chart shows all active (started but not completed) work, ordered by their parent(s).
      </p>
    HTML
  end

  def run
    aging_issues = @issues.select do |issue|
      cycletime = issue.board.cycletime
      cycletime.started_time(issue) && cycletime.stopped_time(issue).nil?
    end
    group_hierarchy aging_issues
    # all_parents = aging_issues
  end

  def group_hierarchy issues
    inserted_keys = {}
    result = []
    issues.each do |issue|
      hierarchy = hierarchy_for issue
      hierarchy.reverse.each do |node|
        row = inserted_keys[node.key]
        if row.nil?
          inserted_keys[node.key] = Row.new(issue: issue, is_primary_issue: (node == issue))
        end

      end
      result << Row.new(issue: issue, is_primary_issue: true, indent_level: 0)
      parent = issue.parent
      while parent
        result << Row.new(issue: parent, is_primary_issue: false, indent_level: 0)
        parent = parent.parent
      end
    end

    result.sort do |a, b|
      a_parents = hierarchy_for(a.issue)
      b_parents = hierarchy_for(b.issue)
      if a.parent == b.parent
        a.key <=> b.key
      elsif a.parent
      end
    end

    result
  end

  def hierarchy_for issue
    result = []
    result << issue

    parent = issue.parent
    while parent
      result << parent
      parent = parent.parent
    end
    result
  end
end
