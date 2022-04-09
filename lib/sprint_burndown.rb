# frozen_string_literal: true

class SprintBurndown < ChartBase
  def run
    sprints = sprints_in_time_range
    return nil if sprints.empty?

    sprints.each do |sprint|
      puts "BURNDOWN: #{sprint.inspect}"
    end

    '<div>SprintBurndown goes here</div>'
  end
end

