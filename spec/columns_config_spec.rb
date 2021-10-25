# frozen_string_literal: true

require './spec/spec_helper'

class Issue
  def one config
    "one-#{config.class}"
  end

  def two config, arg1
    "two-#{config.class}-#{arg1}"
  end

  def three arg1
    "three-#{arg1}"
  end
end

describe ColumnsConfig do
  context 'method_missing and responds_to_missing?' do
    # Note that the way we test responds_to_missing? is by calling respond_to? Non-intuitive.

    issue = load_issue 'SP-2'
    file = FileConfig.new project_config: nil, block: nil

    it 'should call a method with config but no args' do
      columns = ColumnsConfig.new file_config: file, block: nil
      proc = columns.one

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'one-ColumnsConfig'
    end

    it 'should call a method with config and args' do
      columns = ColumnsConfig.new file_config: file, block: nil
      proc = columns.two 2

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'two-ColumnsConfig-2'
    end

    it 'should call a method without config and no args' do
      columns = ColumnsConfig.new file_config: file, block: nil
      proc = columns.three 3

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'three-3'
      expect(columns.respond_to?(:three)).to be_truthy
    end

    it "should fail when calling a method that doesn't exist anywhere" do
      columns = ColumnsConfig.new file_config: file, block: nil
      expect { columns.method_that_does_not_exist }
        .to raise_error "method_that_does_not_exist isn't a method on Issue or ColumnsConfig"
      expect(columns.respond_to?(:method_that_does_not_exist)).to be_falsey
    end
  end

  context 'run' do
    it 'should execute the original block that had been passed in, in its own context' do
      columns = ColumnsConfig.new file_config: nil, block: ->(_) { self.class.to_s }
      expect(columns.run).to eq('ColumnsConfig')
    end
  end

  context 'simple columns' do
    it 'should handle string types' do
      config = ColumnsConfig.new file_config: nil, block: nil
      config.string('foo', ->(issue) { "string:#{issue}" })
      actual = config.columns.collect { |type, name, proc| [type, name, proc.call(1)] }
      expect(actual).to eq [[:string, 'foo', 'string:1']]
    end

    it 'should handle date types' do
      config = ColumnsConfig.new file_config: nil, block: nil
      config.date('foo', ->(issue) { "date:#{issue}" })
      actual = config.columns.collect { |type, name, proc| [type, name, proc.call(1)] }
      expect(actual).to eq [[:date, 'foo', 'date:1']]
    end
  end

  context 'column_entry_times' do
    it 'should fail if no board id set and there are no boards' do
      project_config = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      file_config = FileConfig.new project_config: project_config, block: nil
      config = ColumnsConfig.new file_config: file_config, block: nil

      expect { config.column_entry_times }.to raise_error %r{we couldn't find any configuration files}
    end

    it 'should fail if no board id set and there are multiple boards' do
      project_config = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      project_config.load_board_configuration(board_id: 2, filename: 'spec/testdata/sample_board_1_configuration.json')
      project_config.load_board_configuration(board_id: 3, filename: 'spec/testdata/sample_board_1_configuration.json')

      file_config = FileConfig.new project_config: project_config, block: nil
      config = ColumnsConfig.new file_config: file_config, block: nil

      expect { config.column_entry_times }.to raise_error %r{following board ids and this is ambiguous}
    end

    it 'should succeed' do
      project_config = ProjectConfig.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      project_config.load_board_configuration(board_id: 1, filename: 'spec/testdata/sample_board_1_configuration.json')
      file_config = FileConfig.new project_config: project_config, block: nil
      columns_config = ColumnsConfig.new file_config: file_config, block: nil
      columns_config.column_entry_times
      actual = columns_config.columns.collect { |type, name, _proc| [type, name] }
      expect(actual).to eq [
        [:date, 'Backlog'],
        [:date, 'Ready'],
        [:date, 'In Progress'],
        [:date, 'Review'],
        [:date, 'Done']
      ]
    end
  end
end
