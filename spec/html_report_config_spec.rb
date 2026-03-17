# frozen_string_literal: true

require './spec/spec_helper'

class TestableChart < ChartBase
  attr_accessor :issues, :cycletime, :board_columns, :time_range, :date_range

  def initialize _block
    super()
  end

  def run
    'running'
  end
end

describe HtmlReportConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:project_config) do
    exporter.file_system.when_loading file: 'spec/complete_sample/sample_statuses.json', json: :not_mocked
    exporter.file_system.when_loading file: 'spec/complete_sample/sample_board_1_configuration.json', json: :not_mocked

    project_config = ProjectConfig.new(
      exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
    )
    project_config.file_prefix 'sample'
    project_config.time_range = Time.parse('2022-01-01')..Time.parse('2022-02-01')
    project_config.load_status_category_mappings
    project_config.load_all_boards
    project_config
  end
  let(:file_config) { FileConfig.new project_config: project_config, block: nil }

  context 'no injectable dependencies' do
    it 'still passes if no dependencies supported' do
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
    before do
      ['lib/jirametrics/html/index.css', 'Gemfile'].each do |unmocked_file|
        exporter.file_system.when_loading file: unmocked_file, json: :not_mocked
      end
    end

    it 'loads standard css' do
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to be_empty
    end

    it 'fails to load missing extra css' do
      project_config.settings['include_css'] = 'not_found.css'
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to eq [
        'Unable to find specified CSS file: not_found.css'
      ]
    end

    it 'loads extra css' do
      project_config.settings['include_css'] = 'Gemfile' # It just needs to be a text file and this is handy.
      config = described_class.new file_config: file_config, block: nil
      config.load_css html_directory: 'lib/jirametrics/html'
      expect(exporter.file_system.log_messages).to eq [
        'Loaded CSS:  Gemfile'
      ]
    end
  end

  context 'create_footer' do
    let(:now) { DateTime.parse '2010-01-02T01:02:03 +0000' }

    it 'parses with unpackaged version' do
      config = described_class.new file_config: file_config, block: nil
      expect(config.create_footer now: now).to eq <<~HTML
        <section id="footer">
          Report generated on <b>2010-Jan-02</b> at <b>01:02:03am +00:00</b>
          with <a href="https://jirametrics.org">JiraMetrics</a> <b>vNext</b>
        </section>
      HTML
    end

    it 'parses with packaged version' do
      config = described_class.new file_config: file_config, block: nil
      Gem.loaded_specs['jirametrics'] = Gem::Version.create('1.0.0')
      expect(config.create_footer now: now).to eq <<~HTML
        <section id="footer">
          Report generated on <b>2010-Jan-02</b> at <b>01:02:03am +00:00</b>
          with <a href="https://jirametrics.org">JiraMetrics</a> <b>v1.0.0</b>
        </section>
      HTML
    ensure
      Gem.loaded_specs['jirametrics'] = nil
    end

    it 'parses with timezone offset' do
      config = described_class.new file_config: file_config, block: nil
      exporter.timezone_offset '+0200'
      expect(config.create_footer now: now).to eq <<~HTML
        <section id="footer">
          Report generated on <b>2010-Jan-02</b> at <b>03:02:03am +02:00</b>
          with <a href="https://jirametrics.org">JiraMetrics</a> <b>vNext</b>
        </section>
      HTML
    end
  end

  context 'define chart' do
    it 'Tracks deprecated warnings' do
      described_class.define_chart(
        name: 'fake_chart', classname: 'TestableChart',
        deprecated_warning: 'Please use another', deprecated_date: '2024-05-23'
      )

      config = described_class.new file_config: file_config, block: nil
      config.fake_chart
      expect(config.file_system.log_messages).to match_strings [
        /^Deprecated\(2024-05-23\): Please use another/
      ]
    end
  end

  context 'generated_colors accumulation' do
    let(:config) do
      described_class.new(file_config: file_config, block: nil).tap do |c|
        c.board_id 1
      end
    end

    it 'initialises @generated_colors to an empty hash' do
      expect(config.instance_variable_get(:@generated_colors)).to eq({})
    end

    it 'merges generated_colors from a chart after execute_chart' do
      chart = TestableChart.new(nil)
      def chart.run
        @generated_colors['--generated-color-aabbccdd'] = { light: '#4bc14b', dark: '#2a7a2a' }
        'html'
      end
      config.execute_chart chart
      expect(config.instance_variable_get(:@generated_colors)).to eq(
        '--generated-color-aabbccdd' => { light: '#4bc14b', dark: '#2a7a2a' }
      )
    end

    it 'merges idempotently when two charts use the same pair' do
      pair = { light: '#4bc14b', dark: '#2a7a2a' }
      2.times do
        chart = TestableChart.new(nil)
        chart.define_singleton_method(:run) do
          @generated_colors['--generated-color-aabbccdd'] = pair
          'html'
        end
        config.execute_chart chart
      end
      expect(config.instance_variable_get(:@generated_colors).size).to eq 1
    end

    it 'resets chart.generated_colors to {} before each run' do
      chart = TestableChart.new(nil)
      chart.generated_colors = { '--generated-color-old' => { light: 'red', dark: 'darkred' } }
      colors_at_run_start = nil
      chart.define_singleton_method(:run) do
        colors_at_run_start = @generated_colors.dup
        'html'
      end
      config.execute_chart chart
      expect(colors_at_run_start).to eq({})
    end
  end

  context 'load_css with generated colors' do
    before do
      ['lib/jirametrics/html/index.css', 'Gemfile'].each do |unmocked_file|
        exporter.file_system.when_loading file: unmocked_file, json: :not_mocked
      end
    end

    let(:config) do
      described_class.new(file_config: file_config, block: nil).tap do |c|
        c.board_id 1
      end
    end

    it 'appends nothing when generated_colors is empty' do
      base_css = config.load_css(html_directory: 'lib/jirametrics/html')
      config2 = described_class.new(file_config: file_config, block: nil)
      config2.board_id 1
      config2.instance_variable_set(:@generated_colors, {})
      expect(config2.load_css(html_directory: 'lib/jirametrics/html')).to eq base_css
    end

    it 'appends all three selectors when generated_colors is non-empty' do
      config.instance_variable_set(:@generated_colors, {
        '--generated-color-aabbccdd' => { light: '#4bc14b', dark: '#2a7a2a' }
      })
      css = config.load_css(html_directory: 'lib/jirametrics/html')
      expect(css).to include(':root')
      expect(css).to include('--generated-color-aabbccdd: #4bc14b')
      expect(css).to include('@media (prefers-color-scheme: dark)')
      expect(css).to include('html[data-theme="dark"]')
      expect(css).to include('--generated-color-aabbccdd: #2a7a2a')
    end
  end
end
