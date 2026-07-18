# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cumulative_flow_diagram'

describe CumulativeFlowDiagram do
  let(:board) { load_complete_sample_board.tap { |b| b.cycletime = default_cycletime_config } }
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

  describe '#run' do
    it 'renders without error' do
      expect { chart.run }.not_to raise_error
    end

    it 'includes the board column names' do
      output = chart.run
      # complete_sample board visible columns: Ready, In Progress, Review, Done
      aggregate_failures do
        expect(output).to include('Ready')
        expect(output).to include('In Progress')
        expect(output).to include('Done')
      end
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

    describe '#column_rules' do
      def chart_with_rules &block
        c = described_class.new(block)
        c.file_system = MockFileSystem.new
        c.file_system.when_loading(
          file: File.expand_path('./lib/jirametrics/html/cumulative_flow_diagram.erb'),
          json: :not_mocked
        )
        c.board_id = 1
        c.all_boards = { 1 => board }
        c.issues = issues
        c.date_range = Date.parse('2021-06-01')..Date.parse('2021-09-01')
        c
      end

      it 'uses a custom colour for the named column' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.color = '#abcdef' if column.name == 'In Progress'
          end
        end.run
        expect(output).to include('#abcdef')
      end

      it 'excludes an ignored column from the output' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.ignore if column.name == 'Done'
          end
        end.run
        # 'Done' must not appear as a dataset label
        expect(output).not_to include('"Done"')
      end

      it 'still includes non-ignored columns when one is ignored' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.ignore if column.name == 'Done'
          end
        end.run
        expect(output).to include('In Progress')
      end

      it 'uses the custom label in place of the column name' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.label = 'WIP' if column.name == 'In Progress'
          end
        end.run
        aggregate_failures do
          expect(output).to include('"label":"WIP"')
          expect(output).not_to include('"label":"In Progress"')
        end
      end

      it 'includes label_hint in the dataset JSON when set' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.label_hint = 'Items actively being worked on' if column.name == 'In Progress'
          end
        end.run
        expect(output).to include('Items actively being worked on')
      end

      it 'includes the legend hover tooltip plugin when label_hint is used' do
        output = chart_with_rules do
          column_rules do |column, rule|
            rule.label_hint = 'Some hint' if column.name == 'In Progress'
          end
        end.run
        aggregate_failures do
          expect(output).to include('onHover')
          expect(output).to include('legendItem')
        end
      end

      # rubocop:disable RSpec/NestedGroups
      describe '#triangle_color' do
        it 'uses a dark/light pair by default' do
          output = chart_with_rules {}.run # rubocop:disable Lint/EmptyBlock
          aggregate_failures do
            expect(output).to include('"#333333"')
            expect(output).to include('"#ffffff"')
          end
        end

        it 'uses the configured color' do
          output = chart_with_rules { triangle_color '#abcdef' }.run
          expect(output).to include('"#abcdef"')
        end

        it 'supports a light/dark color pair' do
          output = chart_with_rules { triangle_color ['#111111', '#eeeeee'] }.run
          aggregate_failures do
            expect(output).to include('"#111111"')
            expect(output).to include('"#eeeeee"')
          end
        end
      end

      describe '#arrival_rate_line_color' do
        it 'uses the default orange when not configured' do
          output = chart_with_rules {}.run # rubocop:disable Lint/EmptyBlock
          expect(output).to include('"rgba(255,138,101,0.85)"')
        end

        it 'uses the configured color' do
          output = chart_with_rules { arrival_rate_line_color '#112233' }.run
          expect(output).to include('"#112233"')
        end

        it 'supports a light/dark color pair' do
          output = chart_with_rules { arrival_rate_line_color ['#112233', '#aabbcc'] }.run
          aggregate_failures do
            expect(output).to include('"#112233"')
            expect(output).to include('"#aabbcc"')
          end
        end

        it 'suppresses the line when nil is passed' do
          output = chart_with_rules { arrival_rate_line_color nil }.run
          expect(output).not_to include('"rgba(255,138,101,0.85)"')
        end
      end

      describe '#departure_rate_line_color' do
        it 'uses the default teal when not configured' do
          output = chart_with_rules {}.run # rubocop:disable Lint/EmptyBlock
          expect(output).to include('"rgba(128,203,196,0.85)"')
        end

        it 'uses the configured color' do
          output = chart_with_rules { departure_rate_line_color '#aabbcc' }.run
          expect(output).to include('"#aabbcc"')
        end

        it 'supports a light/dark color pair' do
          output = chart_with_rules { departure_rate_line_color ['#223344', '#ddeeff'] }.run
          aggregate_failures do
            expect(output).to include('"#223344"')
            expect(output).to include('"#ddeeff"')
          end
        end

        it 'suppresses the line when nil is passed' do
          output = chart_with_rules { departure_rate_line_color nil }.run
          expect(output).not_to include('"rgba(128,203,196,0.85)"')
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end

  describe '#build_data_sets' do
    it 'builds one coloured dataset per column, reversed, with correction-window segments' do
      chart.date_range = Date.parse('2021-06-01')..Date.parse('2021-06-02')
      rule = Struct.new(:label, :label_hint)
      result = chart.send(
        :build_data_sets,
        columns: %w[Ready Done],
        correction_windows: [
          { column_index: 0, start_date: Date.parse('2021-06-01'), end_date: Date.parse('2021-06-02') }
        ],
        active_rules: [rule.new(nil, 'ready hint'), rule.new('DoneLabel', nil)],
        daily_marginals: { Date.parse('2021-06-01') => [3, 1], Date.parse('2021-06-02') => [2, 2] },
        fill_colors: %w[fill0 fill1],
        border_colors: %w[border0 border1]
      )

      aggregate_failures do
        # Reversed: rightmost column (Done) first. Done keeps its label; Ready falls back to the column name.
        expect(result.map { |ds| ds[:label] }).to eq %w[DoneLabel Ready]
        expect(result.map { |ds| ds[:label_hint] }).to eq [nil, 'ready hint']
        expect(result.map { |ds| ds[:backgroundColor] }).to eq %w[fill1 fill0]
        expect(result.map { |ds| ds[:borderColor] }).to eq %w[border1 border0]
        expect(result.map { |ds| [ds[:fill], ds[:tension]] }).to eq [[true, 0], [true, 0]]
        expect(result.map { |ds| ds[:data] }).to eq [
          [{ x: '2021-06-01', y: 1 }, { x: '2021-06-02', y: 2 }],
          [{ x: '2021-06-01', y: 3 }, { x: '2021-06-02', y: 2 }]
        ]
        # Only the Ready column (index 0) had a correction window, so only its segment carries the dates.
        expect(result[0][:segment].to_json).not_to include('2021-06-01')
        expect(result[1][:segment].to_json).to include('["2021-06-01", "2021-06-02"]')
      end
    end
  end
end
