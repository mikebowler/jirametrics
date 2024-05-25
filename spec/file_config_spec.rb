# frozen_string_literal: true

require './spec/spec_helper'

describe FileConfig do
  let(:exporter) { Exporter.new file_system: MockFileSystem.new }
  let(:project_config) do
    project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
    project_config.file_prefix 'sample'
    project_config.load_status_category_mappings
    project_config.load_all_boards
    project_config
  end
  let(:file_config) do
    described_class.new project_config: project_config, block: empty_config_block, today: to_date('2024-01-01')
  end

  context 'conversions' do
    it 'converts string' do
      expect(file_config.to_string(5)).to eql '5'
    end

    it 'converts date with null' do
      time = Time.now
      expect(file_config.to_date(time)).to eql time.to_date
    end

    it 'converts nil to date' do
      expect(file_config.to_date(nil)).to be_nil
    end
  end

  context 'sort all rows' do
    it 'sorts nils to the bottom' do
      input = [[nil, 1], [1, 2], [nil, 3], [4, 4]]
      expected = [[1, 2], [4, 4], [nil, 3], [nil, 1]]
      expect(file_config.sort_output(input)).to eq expected
    end
  end

  context 'output_filename' do
    it 'creates filename' do
      file_config.file_suffix '.csv'
      expect(file_config.output_filename).to eq 'spec/testdata/sample.csv'
    end
  end

  context 'prepare_grid' do
    it 'prepares grid without headers' do
      file_config.columns do
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set :@issues, issues

      expect(file_config.prepare_grid).to eq([
        ['SP-1', 'Create new draft event'],
        ['SP-10', 'Check in people at an event']
      ])
    end

    it 'prepares grid with headers' do
      file_config.columns do
        write_headers true
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set :@issues, issues

      expect(file_config.prepare_grid).to eq([
        %w[id summary],
        ['SP-1', 'Create new draft event'],
        ['SP-10', 'Check in people at an event']
      ])
    end

    it 'prepares grid only_use_row_if' do
      file_config.only_use_row_if do |row|
        !row[1].include? 'Create'
      end
      file_config.columns do
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set :@issues, issues

      expect(file_config.prepare_grid).to eq([
        ['SP-10', 'Check in people at an event']
      ])
    end
  end

  context 'columns' do
    it 'raises error if multiples are set' do
      file_config.columns { 'a' }
      expect { file_config.columns { 'a' } }.to raise_error(/Can only have one/)
    end
  end

  context 'run' do
    it 'raises error if neither columns or html_report specified' do
      file_config = described_class.new project_config: project_config, block: empty_config_block
      expect { file_config.run }.to raise_error('Must specify one of "columns" or "html_report"')
    end

    it 'writes a csv' do
      project_config.issues << load_issue('SP-1')
      file_config.columns do
        write_headers true

        date 'created', created
        string 'Key', key
      end
      file_config.run
      expect(exporter.file_system.saved_files).to eq({
        'spec/testdata/sample-2024-01-01.csv' => "created,Key\n2021-06-18,SP-1\n"
      })
    end
  end
end
