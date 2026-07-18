# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/mcp_server'

describe McpServer do
  # Board from the complete sample: Ready(10001), In Progress(3), Review(10011), Done(10002).
  let(:board) { load_complete_sample_board }

  describe '.resolve_projects' do
    it 'returns nil (no filter) when no project is given' do
      expect(described_class.resolve_projects({ aggregates: {} }, nil)).to be_nil
    end

    it 'wraps a plain project name in a one-element allow-list' do
      expect(described_class.resolve_projects({ aggregates: {} }, 'SP')).to eq ['SP']
    end

    it 'expands an aggregate name to its constituent projects' do
      context = { aggregates: { 'Everything' => %w[SP FOO] } }
      expect(described_class.resolve_projects(context, 'Everything')).to eq %w[SP FOO]
    end

    it 'treats a missing aggregates key as no aggregates' do
      expect(described_class.resolve_projects({}, 'SP')).to eq ['SP']
    end
  end

  describe '.column_name_for' do
    it 'returns the visible column that owns the status id' do
      expect(described_class.column_name_for(board, 3)).to eq 'In Progress'
    end

    it 'returns nil when no visible column owns the status id' do
      expect(described_class.column_name_for(board, 999_999)).to be_nil
    end
  end

  describe '.matches_blocked_stalled?' do
    # bsc entries only need to answer blocked?/stalled?
    def change blocked: false, stalled: false
      Struct.new(:is_blocked, :is_stalled) do
        def blocked? = is_blocked
        def stalled? = is_stalled
      end.new(blocked, stalled)
    end

    def matches? bsc, ever_blocked: nil, ever_stalled: nil, currently_blocked: nil, currently_stalled: nil
      McpServer.matches_blocked_stalled?(bsc, ever_blocked, ever_stalled, currently_blocked, currently_stalled)
    end

    it 'matches everything when no blocked/stalled filter is set' do
      expect(matches?([])).to be true
    end

    it 'ever_blocked requires at least one blocked entry' do
      aggregate_failures do
        expect(matches?([change(blocked: true)], ever_blocked: true)).to be true
        expect(matches?([change(blocked: false)], ever_blocked: true)).to be false
        expect(matches?([], ever_blocked: true)).to be false
      end
    end

    it 'ever_stalled requires at least one stalled entry' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], ever_stalled: true)).to be true
        expect(matches?([change(stalled: false)], ever_stalled: true)).to be false
      end
    end

    it 'currently_blocked requires the LAST entry to be blocked' do
      aggregate_failures do
        expect(matches?([change(blocked: false), change(blocked: true)], currently_blocked: true)).to be true
        expect(matches?([change(blocked: true), change(blocked: false)], currently_blocked: true)).to be false
        expect(matches?([], currently_blocked: true)).to be false # last is nil
      end
    end

    it 'currently_stalled requires the LAST entry to be stalled' do
      aggregate_failures do
        expect(matches?([change(stalled: true)], currently_stalled: true)).to be true
        expect(matches?([change(stalled: false)], currently_stalled: true)).to be false
        expect(matches?([], currently_stalled: true)).to be false # last is nil
      end
    end
  end
end
