# frozen_string_literal: true

require 'jirametrics/cfd_data_builder'

class CumulativeFlowDiagram < ChartBase
  # Used to embed a Chart.js segment callback (which contains JS functions) into
  # a JSON-like dataset object. The custom to_json emits raw JS rather than a
  # quoted string, following the same pattern as ExpeditedChart::EXPEDITED_SEGMENT.
  class Segment
    def initialize windows
      # Build a JS array literal of [start_date, end_date] string pairs
      @windows_js = windows
        .map { |w| "[#{w[:start_date].to_json}, #{w[:end_date].to_json}]" }
        .join(', ')
    end

    def to_json *_args
      <<~JS
        {
          borderDash: function(ctx) {
            const x = ctx.p1.parsed.x;
            const windows = [#{@windows_js}];
            return windows.some(function(w) {
              return x >= new Date(w[0]).getTime() && x <= new Date(w[1]).getTime();
            }) ? [6, 4] : undefined;
          }
        }
      JS
    end
  end
  private_constant :Segment

  def initialize block
    super()
    header_text 'Cumulative Flow Diagram'
    instance_eval(&block)
  end

  def run
    cfd = CfdDataBuilder.new(
      board: current_board,
      issues: issues,
      date_range: date_range
    ).run

    columns            = cfd[:columns]
    daily_counts       = cfd[:daily_counts]
    correction_windows = cfd[:correction_windows]
    column_count       = columns.size

    # Convert cumulative totals to marginal band heights for Chart.js stacking.
    # cumulative[i] = issues that reached column i or further.
    # marginal[i]   = cumulative[i] - cumulative[i+1]  (last column: marginal = cumulative)
    daily_marginals = daily_counts.transform_values do |cumulative|
      cumulative.each_with_index.map do |count, i|
        i < column_count - 1 ? count - cumulative[i + 1] : count
      end
    end

    border_colors = columns.map { random_color }
    fill_colors   = border_colors.map { |c| hex_to_rgba(c, 0.35) }

    # Datasets in reversed order: rightmost column first (bottom of stack), leftmost last (top).
    data_sets = columns.each_with_index.map do |name, col_index|
      col_windows = correction_windows
        .select { |w| w[:column_index] == col_index }
        .map { |w| { start_date: w[:start_date].to_s, end_date: w[:end_date].to_s } }

      {
        label: name,
        data: date_range.map { |date| { x: date.to_s, y: daily_marginals[date][col_index] } },
        backgroundColor: fill_colors[col_index],
        borderColor: border_colors[col_index],
        fill: true,
        tension: 0,
        segment: Segment.new(col_windows)
      }
    end.reverse

    # Correction windows for the afterDraw hatch plugin, with dataset index in
    # Chart.js dataset array (reversed: done column = index 0).
    hatch_windows = correction_windows.map do |w|
      {
        dataset_index: column_count - 1 - w[:column_index],
        start_date: w[:start_date].to_s,
        end_date: w[:end_date].to_s,
        color: border_colors[w[:column_index]]
      }
    end

    wrap_and_render(binding, __FILE__)
  end

  private

  def hex_to_rgba hex, alpha
    r, g, b = hex.delete_prefix('#').scan(/../).map { |c| c.to_i(16) }
    "rgba(#{r}, #{g}, #{b}, #{alpha})"
  end
end
