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

    instance_eval(&@block)
  end

  def cycletime label = nil, &block
    if @board.cycletime
      raise "Cycletime has already been set for board #{id}. Did you also set it inside the html_report? " \
        'If so, remove it from there.'
    end

    @board.cycletime = CycleTimeConfig.new(parent_config: self, label: label, block: block)
  end

  def expedited_priority_names *priority_names
    project_config.exporter.file_system.deprecated(
      date: '2024-09-15', message: 'Expedited priority names are now specified in settings'
    )
    @project_config.settings['expedited_priority_names'] = priority_names
  end
end
