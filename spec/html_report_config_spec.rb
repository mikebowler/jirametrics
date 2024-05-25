# frozen_string_literal: true

require './spec/spec_helper'

class TestableChart < ChartBase
  attr_accessor :issues, :cycletime, :board_columns, :time_range, :date_range

  def run
    'running'
  end
end

describe HtmlReportConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:project_config) do
    project_config = ProjectConfig.new(
      exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
    )
    project_config.file_prefix 'sample'
    project_config.load_status_category_mappings
    project_config.load_all_boards
    project_config
  end
  let(:file_config) { FileConfig.new project_config: project_config, block: nil }

  context 'no injectable dependencies' do
    it 'still passes if no dependencies supported' do
      project_config.time_range = Time.parse('2022-01-01')..Time.parse('2022-02-01')
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

  it 'shouldnt allow multiple cycletimes' do
    config = described_class.new file_config: file_config, block: nil
    config.cycletime '1st', &empty_config_block
    expect { config.cycletime '2nd', &empty_config_block }.to raise_error 'Multiple cycletimes not supported'
  end

  context 'load_css' do
    it 'loads standard css' do
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to eq [
        'Loaded CSS:  lib/jirametrics/html/index.css'
      ]
    end

    it 'fails to load missing extra css' do
      project_config.settings['include_css'] = 'not_found.css'
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to eq [
        'Loaded CSS:  lib/jirametrics/html/index.css',
        'Unable to find specified CSS file: not_found.css'
      ]
    end

    it 'loads extra css' do
      project_config.settings['include_css'] = 'Gemfile' # It just needs to be a text file and this is handy.
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to eq [
        'Loaded CSS:  lib/jirametrics/html/index.css',
        'Loaded CSS:  Gemfile'
      ]
    end
  end
end
