# frozen_string_literal: true

require './spec/spec_helper'
require './spec/mock_file_system'

# Testing main entrypoint
describe JiraMetrics do
  let(:jirametrics) { described_class.new }
  let(:mock_file_system) { MockFileSystem.new }

  it 'does not find config' do
    jirametrics.load_config 'missing_config', file_system: mock_file_system
    raise 'It should have exited'
  rescue SystemExit
    expect(mock_file_system.log_messages).to eq([
      'Error: Cannot find configuration file "missing_config"'
    ])
  end

  it 'calls load with the absolute path of the config file' do
    mock_file_system.when_loading file: 'my_config.rb', json: ''
    expect(jirametrics).to receive(:load).with(File.absolute_path('my_config.rb')) # rubocop:disable RSpec/MessageSpies
    jirametrics.load_config 'my_config.rb', file_system: mock_file_system
  end
end
