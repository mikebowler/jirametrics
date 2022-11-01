# frozen_string_literal: true

class BoardConfig
  attr_reader :id, :project_config

  def initialize id:, block:, project_config:
    @id = id
    @block = block
    @project_config = project_config
  end

  def run
    instance_eval(&@block)
  end

  def cycletime label = nil, &block
    board = @project_config.all_boards[id]
    if board.cycletime
      raise "Cycletime has already been set for board #{id}. Did you also set it inside the html_report? " \
        'If so, remove it from there.'
    end

    board.cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
  end
end
