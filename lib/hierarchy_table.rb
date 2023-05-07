# frozen_string_literal: true

require './lib/chart_base'

class HierarchyTable < ChartBase
  def initialize block = nil
    super()

    header_text 'Hierarchy Table'
    description_text <<-HTML
      <p>content goes here</p>
    HTML

    instance_eval(&block) if block
  end

  def run
    tree_organizer = TreeOrganizer.new issues: @issues
    wrap_and_render(binding, __FILE__)
  end
end
