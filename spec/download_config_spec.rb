# frozen_string_literal: true

require './spec/spec_helper'

describe DownloadConfig do
  context 'run' do
    it 'should execute the original block that had been passed in, in its own context' do
      columns = DownloadConfig.new project_config: nil, block: ->(_) { self.class.to_s }
      expect(columns.run).to eq('DownloadConfig')
    end
  end
end
