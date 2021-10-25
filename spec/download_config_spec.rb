# frozen_string_literal: true

require './spec/spec_helper'

describe DownloadConfig do
  context 'jql' do
    it 'makes from project' do
      download_config = DownloadConfig.new project_config: nil, block: nil
      download_config.project_key 'a'
      expect(download_config.jql).to eql 'project="a"'
    end

    it 'makes from project and rolling date count' do
      download_config = DownloadConfig.new project_config: nil, block: nil
      download_config.rolling_date_count 90
      today = DateTime.parse('2021-08-01')
      expected = '((status changed AND resolved = null) OR (status changed DURING ("2021-05-03 00:00","2021-08-01")))'
      expect(download_config.jql(today: today)).to eql expected
    end

    it 'makes from filter' do
      download_config = DownloadConfig.new project_config: nil, block: nil
      download_config.filter_name 'a'
      expect(download_config.jql).to eql 'filter="a"'
    end

    it 'makes from jql' do
      download_config = DownloadConfig.new project_config: nil, block: nil
      download_config.jql = 'foo=bar'
      expect(download_config.jql).to eql 'foo=bar'
    end

    it 'throws exception when everything nil' do
      download_config = DownloadConfig.new project_config: nil, block: nil
      expect { download_config.jql }.to raise_error(/Everything was nil/)
    end
  end

  context 'run' do
    it 'should execute the original block that had been passed in, in its own context' do
      columns = DownloadConfig.new project_config: nil, block: ->(_) { self.class.to_s }
      expect(columns.run).to eq('DownloadConfig')
    end
  end
end
