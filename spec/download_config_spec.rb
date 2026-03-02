# frozen_string_literal: true

require './spec/spec_helper'

describe DownloadConfig do
  context 'run' do
    it 'executes the original block that had been passed in, in its own context' do
      columns = described_class.new project_config: nil, block: ->(_) { self.class.to_s }
      expect(columns.run).to eq('DownloadConfig')
    end
  end

  context 'github_repo' do
    let(:config) { described_class.new project_config: nil, block: nil }

    it 'accepts owner/repo format directly' do
      config.github_repo 'mikebowler/jirametrics-dev-playground'
      expect(config.github_repos).to eq ['mikebowler/jirametrics-dev-playground']
    end

    it 'extracts owner/repo from a full GitHub URL' do
      config.github_repo 'https://github.com/mikebowler/jirametrics-dev-playground'
      expect(config.github_repos).to eq ['mikebowler/jirametrics-dev-playground']
    end

    it 'handles a trailing slash in the URL' do
      config.github_repo 'https://github.com/mikebowler/jirametrics-dev-playground/'
      expect(config.github_repos).to eq ['mikebowler/jirametrics-dev-playground']
    end

    it 'accepts multiple repos in one call' do
      config.github_repo 'owner/repo1', 'https://github.com/owner/repo2'
      expect(config.github_repos).to eq %w[owner/repo1 owner/repo2]
    end

    it 'accumulates repos across multiple calls' do
      config.github_repo 'owner/repo1'
      config.github_repo 'owner/repo2'
      expect(config.github_repos).to eq %w[owner/repo1 owner/repo2]
    end
  end
end
