# frozen_string_literal: true

class BoardConfig
  attr_reader :id

  def initialize id:, block:, project_config:
    @id = id
    @block = block
    @project_config = project_config
  end

  def run
    instance_eval(&@block)
  end

  def cycletime label = nil, &block
    @project_config.all_boards.each do |_id, board|
      if board.cycletime
        raise 'Cycletime has already been set. Did you also set it inside the html_report? If so, remove it from there.'
      end

      board.cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
    end
  end

end