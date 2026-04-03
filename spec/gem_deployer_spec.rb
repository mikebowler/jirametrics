# frozen_string_literal: true

require './spec/spec_helper'
require './tasks/gem_deployer'

describe GemDeployer do
  let(:gemspec_path) { 'jirametrics.gemspec' }
  let(:changes_path) do
    Tempfile.new(['changes', '.md']).tap { |f| f.write(changes_content) && f.flush }.path
  end
  let(:deployer) { described_class.new(gemspec_path: gemspec_path, changes_path: changes_path) }

  let(:changes_content) do
    <<~MARKDOWN
      ---
      layout: page
      title: Changes
      ---

      # v2.99.0 (April 1, 2026)

      * Fixed a [major bug]({% link config_charts.md %}#some-anchor) in the exporter
      * Improved the [`throughput_chart`]({% link config_charts.md %}#throughput_chart) performance

      # v2.98.0 (March 1, 2026)

      * Some other change
    MARKDOWN
  end

  before do
    allow(deployer).to receive(:current_version).and_return(Gem::Version.new('2.99.0'))
  end

  context 'changelog_section' do
    it 'finds the section for the current version' do
      expect(deployer.changelog_section).to start_with '# v2.99.0'
    end

    it 'does not include the next version section' do
      expect(deployer.changelog_section).not_to include 'v2.98.0'
    end

    it 'returns nil when the version is not in the changelog' do
      allow(deployer).to receive(:current_version).and_return(Gem::Version.new('9.99.0'))
      expect(deployer.changelog_section).to be_nil
    end

    it 'strips Jekyll front matter' do
      expect(deployer.changelog_section).not_to include 'layout:'
    end
  end

  context 'release_notes' do
    it 'strips markdown links leaving just the text' do
      expect(deployer.release_notes).to include 'major bug'
      expect(deployer.release_notes).not_to include '{% link'
      expect(deployer.release_notes).not_to include 'config_charts.md'
    end

    it 'strips inline code links leaving the code text' do
      expect(deployer.release_notes).to include '`throughput_chart`'
      expect(deployer.release_notes).not_to include '#throughput_chart'
    end

    it 'removes the heading line' do
      expect(deployer.release_notes).not_to include '# v2.99.0'
    end

    it 'returns empty string when changelog section is missing' do
      allow(deployer).to receive(:changelog_section).and_return(nil)
      expect(deployer.release_notes).to eq ''
    end
  end

  context 'prereleases_to_yank' do
    let(:all_versions) do
      [
        { version: Gem::Version.new('2.99pre1'), prerelease: true },
        { version: Gem::Version.new('2.99pre2'), prerelease: true },
        { version: Gem::Version.new('2.98.0'), prerelease: false },
        { version: Gem::Version.new('2.97pre1'), prerelease: true },
        { version: Gem::Version.new('2.97.0'), prerelease: false }
      ]
    end

    before { allow(deployer).to receive(:rubygems_versions).and_return(all_versions) }

    it 'returns pre-releases newer than the latest stable version' do
      expect(deployer.prereleases_to_yank).to contain_exactly(
        Gem::Version.new('2.99pre1'),
        Gem::Version.new('2.99pre2')
      )
    end

    it 'does not include pre-releases from before the previous stable release' do
      expect(deployer.prereleases_to_yank).not_to include Gem::Version.new('2.97pre1')
    end

    it 'returns all pre-releases when no stable version is deployed' do
      allow(deployer).to receive(:rubygems_versions).and_return([
        { version: Gem::Version.new('2.99pre1'), prerelease: true },
        { version: Gem::Version.new('2.99pre2'), prerelease: true }
      ])
      expect(deployer.prereleases_to_yank).to contain_exactly(
        Gem::Version.new('2.99pre1'),
        Gem::Version.new('2.99pre2')
      )
    end

    it 'returns empty when there are no pre-releases since the last stable' do
      allow(deployer).to receive(:rubygems_versions).and_return([
        { version: Gem::Version.new('2.98.0'), prerelease: false }
      ])
      expect(deployer.prereleases_to_yank).to be_empty
    end
  end
end
