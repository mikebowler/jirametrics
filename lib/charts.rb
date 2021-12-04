# frozen_string_literal: true

# Very rough proof of concept code. Do not use for anything serious.

require 'json'
require 'csv'

class HTMLReport
  def run issues
    @all_issues = issues

    File.open('chart.html', 'w') do |file|
      @file = file
      @file.puts '<html><head>'

      @file.puts '<script src="https://cdn.jsdelivr.net/npm/moment@2.29.1/moment.js"></script>'
      @file.puts '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>'
      @file.puts '<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-moment@^1"></script>'

      @file.puts '</head><body>'
      @file.puts '<div>Hello world</div>'
      cycletime_scatterplot
      @file.puts '</html>'
    end
  end

  def cycletime_scatterplot
    completed_issues = @all_issues.select { |issue| issue.cycle_time }

    colours = %w[blue green orange yellow gray black]
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'label' => type,
        'data' => completed_issues
          .select { |issue| issue.type == type }
          .collect do |issue|
            { 'y' => issue.cycle_time,
              'x' => issue.column_times[-1].to_date,
              'title' => ["#{issue.key} : #{issue.cycle_time} day#{'s' unless issue.cycle_time == 1}",issue.title]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => colours[index]
      }
    end
    @file.puts <<-END
    <div>
      <canvas id="myChart" width="800" height="400"></canvas>
    </div>
    <script>
    const data = {
      datasets: #{JSON.generate(data_sets)}
    };

    const config = {
      type: 'scatter',
      data: data,
      options: {
        title: {
          display: true,
          text:    "Cycletime Scatterplot"
        },
        responsive: false, // If responsive is true then it fills the screen
        scales: {
          x: {
            type: "time",
            time: {
                format: 'YYYY-MM-DD'
            },
            scaleLabel: {
              display: true,
              labelString: 'Date Completed'
            }
          },
          y: {
            scaleLabel: {
              display: true,
              labelString: 'Days'
            }
          }
        },
        plugins: {
          tooltip: {
            callbacks: {
              label: function(context) {
                return context.dataset.data[context.dataIndex].title
              }
            }
          }
        }
      }
    };
    const ctx = document.getElementById('myChart').getContext('2d');
    const myChart = new Chart(ctx,config);
    </script>
    END
  end
end

# ======================== #
# TODO: It's currently hardcoded to know how many columns there will be and what they'll be.
class Issue
  attr_reader :key, :title, :column_times, :type, :cycle_time

  def initialize row
    @key = row[0]
    @title = row[2]
    @column_times = row[3...10].collect { |time| time.nil? ? nil : DateTime.parse(time) }
    @type = row[10].inspect
    @cycle_time = (@column_times[-1] - @column_times[0]).to_i unless @column_times[-1].nil?

    # puts '', row.inspect
    # puts @column_times.inspect
    # puts @cycle_time
  end
end

issues = []
File.foreach('target/sample-aa.csv') do |line|
  next if line =~ /^ID/

  data = Issue.new CSV.parse_line(line)
  issues << data
end

HTMLReport.new.run issues

