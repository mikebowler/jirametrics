# frozen_string_literal: true

# Testing main entrypoint
describe JiraMetrics do
  let(:jirametrics) { described_class.new }
  let(:mock_file_system) { MockFileSystem.new }

  it 'does not find config' do
    expect do
      jirametrics.load_config 'missing_config', file_system: mock_file_system
    end.to raise_error SystemExit
    expect(mock_file_system.log_messages).to eq([
      'Error: Cannot find configuration file "missing_config"'
    ])
  end

  it 'loads sucessfully' do
    mock_file_system.when_loading file: 'my_config.rb', json: 'file_system.log "hello"'
    jirametrics.load_config 'my_config', file_system: mock_file_system
    expect(mock_file_system.log_messages).to eq([
      'hello'
    ])
  end
end
