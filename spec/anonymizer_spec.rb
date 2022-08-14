# frozen_string_literal: true

require './spec/spec_helper'

describe Anonymizer do

  # This is done as an end-to-end test because everything in the anonymizer is interconnected and I was
  # too lazy to figure a clean way of slicing the parts out.

  exporter = Exporter.new
  project_config = ProjectConfig.new(
    exporter: exporter, target_path: 'spec/complete_sample/', jira_config: nil, block: nil
  )
  project_config.file_prefix 'sample'
  project_config.anonymize
  project_config.run

  it 'should have renumbered all issue keys' do
    expect(project_config.issues.collect(&:key).sort).to eq %w[ANON-2 ANON-3 ANON-4 ANON-5 ANON-6 ANON-7]
  end
end
