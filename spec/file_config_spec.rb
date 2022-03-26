# frozen_string_literal: true

require './spec/spec_helper'

describe FileConfig do
  let(:exporter) { Exporter.new }
  let(:config) do
    project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
    project_config.file_prefix 'sample'
    FileConfig.new project_config: project_config, block: nil
  end

  context 'conversions' do
    it 'should convert string' do
      expect(config.to_string(5)).to eql '5'
    end

    it 'should convert date with null' do
      time = Time.now
      expect(config.to_date(time)).to eql time.to_date
    end

    it 'should convert nil to date' do
      expect(config.to_date(nil)).to be_nil
    end
  end

  context 'sort all rows' do
    it 'should sort nils to the bottom' do
      input = [[nil, 1], [1, 2], [nil, 3], [4, 4]]
      expected = [[1, 2], [4, 4], [nil, 3], [nil, 1]]
      expect(config.sort_output(input)).to eq expected
    end
  end

  context 'output_filename' do
    it 'should create filename' do
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'
      file_config = FileConfig.new project_config: project_config, block: nil
      file_config.file_suffix '.csv'
      expect(file_config.output_filename).to eq 'spec/testdata/sample.csv'
    end
  end

  context 'prepare_grid' do
    it 'should prepare grid without headers' do
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'

      file_config = FileConfig.new project_config: project_config, block: nil
      file_config.columns do
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set '@issues', issues

      expect(file_config.prepare_grid).to eq([
        ['SP-1', 'Create new draft event'],
        ['SP-10', 'Check in people at an event']
      ])
    end

    it 'should prepare grid with headers' do
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'
      file_config = FileConfig.new project_config: project_config, block: nil
      file_config.columns do
        write_headers true
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set '@issues', issues

      expect(file_config.prepare_grid).to eq([
        %w[id summary],
        ['SP-1', 'Create new draft event'],
        ['SP-10', 'Check in people at an event']
      ])
    end

    it 'should prepare grid only_use_row_if' do
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'
      file_config = FileConfig.new project_config: project_config, block: nil
      file_config.only_use_row_if do |row|
        row[1] !~ /Create/
      end
      file_config.columns do
        string 'id', key
        string 'summary', summary
      end

      issues = [load_issue('SP-1'), load_issue('SP-10')]
      file_config.instance_variable_set '@issues', issues

      expect(file_config.prepare_grid).to eq([
        ['SP-10', 'Check in people at an event']
      ])
    end
  end

  context 'columns' do
    it 'should raise error if multiples are set' do
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'
      file_config = FileConfig.new project_config: project_config, block: nil
      file_config.columns { 'a' }
      expect { file_config.columns { 'a' } }.to raise_error /Can only have one/
    end
  end
end
