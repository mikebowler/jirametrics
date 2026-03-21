# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cumulative_flow_diagram'

describe CumulativeFlowDiagram do
  let(:board) { load_complete_sample_board }
  let(:issues) { load_complete_sample_issues board: board }

  let(:chart) do
    chart = described_class.new(empty_config_block)
    chart.file_system = MockFileSystem.new
    chart.file_system.when_loading(
      file: File.expand_path('./lib/jirametrics/html/cumulative_flow_diagram.erb'),
      json: :not_mocked
    )
    chart.board_id = 1
    chart.all_boards = { 1 => board }
    chart.issues = issues
    chart.date_range = Date.parse('2021-06-01')..Date.parse('2021-09-01')
    chart
  end

  context 'run' do
    it 'renders without error' do
      expect { chart.run }.not_to raise_error
    end

    it 'includes the board column names' do
      output = chart.run
      # complete_sample board visible columns: Ready, In Progress, Review, Done
      expect(output).to include('Ready')
      expect(output).to include('In Progress')
      expect(output).to include('Done')
    end

    it 'includes the segment callback for dashed lines during correction windows' do
      output = chart.run
      expect(output).to include('borderDash')
    end

    it 'sets x-axis max to one day past date_range.end' do
      output = chart.run
      expect(output).to include('2021-09-02')
    end

    it 'includes legend reverse option for correct left-to-right display' do
      output = chart.run
      expect(output).to include('"reverse":true').or include('reverse: true').or include('reverse:true')
    end
  end
end
