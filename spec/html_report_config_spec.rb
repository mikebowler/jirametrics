# frozen_string_literal: true

require './spec/spec_helper'

class TestableChart < ChartBase
  attr_accessor :issues, :cycletime, :board_columns, :time_range, :date_range

  def run
    'running'
  end
end

describe HtmlReportConfig do
  let(:exporter) { Exporter.new }

  context 'no injectable dependencies' do
    it 'still passes if no dependencies supported' do
      project_config = ProjectConfig.new(
        exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
      )
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      project_config.time_range = Time.parse('2022-01-01')..Time.parse('2022-02-01')
      file_config = FileConfig.new project_config: project_config, block: nil
      config = described_class.new file_config: file_config, block: nil
      config.board_id 1

      chart = ChartBase.new
      def chart.run
        'running'
      end
      config.execute_chart chart
      expect(config.sections).to eq [['running', :body]]
    end
  end

  it 'shouldnt allow multiple cycletimes (yet)' do
    empty_block = ->(_) {}
    project_config = ProjectConfig.new(
      exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
    )
    project_config.file_prefix 'sample'
    project_config.load_status_category_mappings
    project_config.load_all_boards
    file_config = FileConfig.new project_config: project_config, block: nil
    config = described_class.new file_config: file_config, block: nil
    config.cycletime '1st', &empty_block
    expect { config.cycletime '2nd', &empty_block }.to raise_error 'Multiple cycletimes not supported yet'
  end
end
