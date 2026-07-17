# frozen_string_literal: true

require './spec/spec_helper'
require 'open3'
require 'tmpdir'

describe 'spec_helper' do # rubocop:disable RSpec/DescribeClass
  describe '#to_time' do
    it 'parses date only' do
      expect(to_time('2024-01-01').inspect).to eq '2024-01-01 00:00:00 +0000'
    end

    it 'parses date/time' do
      expect(to_time('2024-01-01T12:34:56').inspect).to eq '2024-01-01 12:34:56 +0000'
    end

    it 'parses date/time with fractional seconds' do
      expect(to_time('2024-01-01T12:34:56.789').inspect).to eq '2024-01-01 12:34:56.789 +0000'
    end

    it 'parses date/time with fractional seconds and offset' do
      expect(to_time('2024-01-01T12:34:56.789+10:00').inspect).to eq '2024-01-01 12:34:56.789 +1000'
    end

    it 'parses date/time with offset' do
      expect(to_time('2024-01-01T12:34:56 +10:00').inspect).to eq '2024-01-01 12:34:56 +1000'
    end
  end

  describe '#create_issue_from_aging_data' do
    let(:board) { sample_board }

    it 'creates no issues when no ages' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-30')]
      ]
    end

    it 'creates no issues when all zeros' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [0, 0], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-30')]
      ]
    end

    it 'handles simple data with gaps' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [0, 1, 2], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-29')],
        # Selected for Development is skipped because of the zero.
        ['In Progress', to_time('2024-10-29')],
        ['Review', to_time('2024-10-29T01:00:00')]
      ]
    end

    it 'handles bigger gaps' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [1, 5, 3], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-24')],
        ['Selected for Development', to_time('2024-10-24')],
        ['In Progress', to_time('2024-10-24T01:00:00')],
        ['Review', to_time('2024-10-28T02:00:00')]
      ]
    end
  end

  # RSpec doesn't rescue SystemExit, so a production exit()/abort() that leaks out of an example
  # terminates the whole run early with a misleading partial "0 failures" summary. The guard in
  # spec_helper.rb converts a leaked exit into a normal failure so the suite keeps running. This
  # shells out to a subprocess rspec on a fixture that leaks exit and asserts the run survives.
  # Without the guard the child truncates at the leak and reports "2 examples, 0 failures".
  it 'converts a leaked exit into a failure instead of terminating the run' do
    Dir.mktmpdir do |dir|
      leak = File.join(dir, 'leak_spec.rb')
      File.write(leak, <<~RUBY)
        require './spec/spec_helper'
        RSpec.configure { |c| c.example_status_persistence_file_path = nil }
        describe 'leaker' do
          it('a leaks an exit') { exit 1 }
          it('b still runs after the leak') { expect(true).to be(true) }
        end
      RUBY

      # Reuse the exact interpreter and rspec running this suite rather than a bare
      # `bundle exec rspec`, whose `bundle` resolves off PATH — under JRuby/RVM that can
      # pick a different Ruby and fail to find the gem, which has nothing to do with the guard.
      out, = Open3.capture2e(
        { 'JIRAMETRICS_SUBPROCESS_SPEC' => '1' },
        RbConfig.ruby, Gem.bin_path('rspec-core', 'rspec'), leak, '--seed', '0'
      )

      aggregate_failures do
        expect(out).to include('2 examples, 1 failure')
        expect(out).to include('SystemExit')
      end
    end
  end
end
