# frozen_string_literal: true

require 'jirametrics/chart_base'

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
    unless tree_organizer.cyclical_links.empty?
      message = String.new
      message << '<p>Found cyclical links in the parent hierarchy. This is an error and should be '
      message << 'fixed.</p><ul>'
      tree_organizer.cyclical_links.each do |link|
        message << '<li>' << link.join(' > ') << '</ul>'
      end
      message << '</ul>'
      @description_text += message
    end
    wrap_and_render(binding, __FILE__)
  end
end
