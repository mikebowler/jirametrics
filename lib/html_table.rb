# frozen_string_literal: true

require './lib/chart_base'

class HtmlTable
  attr_reader :headings, :rows

  def initialize
    @headings = []
    @rows = []
  end

  def render
    result = String.new
    result << "<table class='standard'><thead>"
    @headings.each do |heading|
      result << "<th>#{heading}</th>"
    end
    result << '</thead></tbody>'
    @rows.each do |row|
      result << '<tr>'
      row.each do |cell|
        result << "<td>#{cell}</td>"
      end
      result << '/<tr>'
    end
    result << '<tbody></table>'
    result
  end
end
