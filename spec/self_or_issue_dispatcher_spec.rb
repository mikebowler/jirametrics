# frozen_string_literal: true

require './spec/spec_helper'

class Issue
  def three arg1
    "three-#{arg1}"
  end
end

describe SelfOrIssueDispatcher do
  context 'method_missing and responds_to_missing?' do
    # Note that the way we test responds_to_missing? is by calling respond_to? Non-intuitive.

    let(:issue) { load_issue 'SP-2' }
    let(:file) do
      exporter = Exporter.new
      project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/testdata/', jira_config: nil, block: nil
      project_config.file_prefix 'sample'
      project_config.load_status_category_mappings
      project_config.load_all_boards
      FileConfig.new project_config: project_config, block: nil
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
end
