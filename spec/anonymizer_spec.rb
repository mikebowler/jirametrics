# frozen_string_literal: true

require './spec/spec_helper'

describe Anonymizer do

  exporter = Exporter.new
  project_config = ProjectConfig.new exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
  project_config.file_prefix 'sample'
  project_config.anonymize
  project_config.run

  it 'should not blow up' do
    expect(project_config.issues.size).to eq 6
  end
end
