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

class TestableBoardChart < ChartBase
  attr_accessor :board_id

  def initialize _block
    super()
    description_text 'test description'
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

  context 'method_missing' do
    it 'instantiates a chart class that matches the snake_case method name' do
      config = described_class.new file_config: file_config, block: nil
      expect { config.testable_chart }.not_to raise_error
    end

    it 'routes aging_work_bar_chart through method_missing without swallowing errors' do
      config = described_class.new file_config: file_config, block: nil
      config.board_id 1
      allow(config).to receive(:issues).and_return([])
      expect { config.aging_work_bar_chart }.not_to raise_error
    end

    it 'raises an error for an unknown name' do
      config = described_class.new file_config: file_config, block: nil
      expect { config.nonexistent_chart }.to raise_error RuntimeError
    end

    it 'raises an error when the class exists but is not a ChartBase subclass' do
      config = described_class.new file_config: file_config, block: nil
      expect { config.string }.to raise_error RuntimeError
    end

    it 'responds to a valid chart name' do
      config = described_class.new file_config: file_config, block: nil
      expect(config.respond_to?(:testable_chart)).to be true
    end

    it 'does not respond to an unknown name' do
      config = described_class.new file_config: file_config, block: nil
      expect(config.respond_to?(:nonexistent_chart)).to be false
    end

    context 'when the chart class re-declares board_id=' do
      let(:board) { project_config.all_boards[1] }

      it 'creates one chart for the given board_id' do
        config = described_class.new file_config: file_config, block: nil
        config.testable_board_chart board_id: 1

        expect(config.charts.length).to eq 1
        expect(config.charts.first.board_id).to eq 1
      end

      it 'creates one chart per board when no board_id is given' do
        issue = empty_issue created: '2022-01-01', board: board
        config = described_class.new file_config: file_config, block: nil
        allow(config).to receive(:issues).and_return([issue])

        config.testable_board_chart

        expect(config.charts.length).to eq 1
        expect(config.charts.first.board_id).to eq 1
      end
    end
  end

  context 'method_missing with board-specific charts across multiple boards' do
    let(:board) { project_config.all_boards[1] }
    let(:board2) do
      raw = JSON.parse(file_read('spec/complete_sample/sample_board_1_configuration.json'))
      raw['id'] = 2
      raw['name'] = 'Aardvark Board' # sorts before "SP board"
      Board.new(raw: raw, possible_statuses: load_complete_sample_statuses).tap do |b|
        project_config.add_issues([empty_issue(created: '2022-01-01', board: b, key: 'SP-99')])
      end
    end
    let(:two_board_issues) do
      [
        empty_issue(created: '2022-01-01', board: board),
        empty_issue(created: '2022-01-01', board: board2, key: 'SP-99')
      ]
    end

    # guess_board_id raises for non-aggregated projects with multiple boards; the real
    # aggregated code path has aggregated_project? == true so guess_board_id returns nil.
    before { allow(project_config).to receive(:aggregated_project?).and_return(true) }

    it 'orders charts alphabetically by board name' do
      config = described_class.new file_config: file_config, block: nil
      allow(config).to receive(:issues).and_return(two_board_issues)

      config.testable_board_chart

      expect(config.charts.length).to eq 2
      board_names = config.charts.map { |c| project_config.all_boards[c.board_id].name }
      expect(board_names).to eq ['Aardvark Board', 'SP board']
    end

    it 'sets description_text to nil for all but the first chart' do
      config = described_class.new file_config: file_config, block: nil
      allow(config).to receive(:issues).and_return(two_board_issues)

      config.testable_board_chart

      expect(config.charts.length).to eq 2
      expect(config.charts[0].description_text).not_to be_nil
      expect(config.charts[1].description_text).to be_nil
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
end
