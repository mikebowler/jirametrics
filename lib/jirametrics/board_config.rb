# frozen_string_literal: true

class BoardConfig
  attr_reader :id, :project_config, :board

  def initialize id:, block:, project_config:
    @id = id
    @block = block
    @project_config = project_config
  end

  def run
    @board = @project_config.all_boards[id]
    raise "Can't find board #{id.inspect} in #{@project_config.all_boards.keys.inspect}" unless @board

    instance_eval(&@block)
    raise "Must specify a cycletime for board #{@id}" if @board.cycletime.nil?
  end

  def cycletime label = nil, &block
    if @board.cycletime
      raise "Cycletime has already been set for board #{id}. Did you also set it inside the html_report? " \
        'If so, remove it from there.'
    end

    @board.cycletime = CycleTimeConfig.new(
      possible_statuses: project_config.possible_statuses,
      label: label, block: block, file_system: project_config.file_system,
      settings: project_config.settings
    )
  end
end
