# frozen_string_literal: true

# Very rough proof of concept code. Do not use for anything serious.

require 'json'
require 'csv'

class HTMLReport
  def initialize
    @colours = %w[blue green orange yellow gray black]
  end

  def run issues:, column_headings:
    @all_issues = issues
    @column_headings = column_headings
    puts @column_headings

    File.open('chart.html', 'w') do |file|
      @file = file
      @file.puts '<html><head>'

      @file.puts '<script src="https://cdn.jsdelivr.net/npm/moment@2.29.1/moment.js"></script>'
      @file.puts '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>'
      @file.puts '<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-moment@^1"></script>'

      @file.puts '</head><body>'
      @file.puts '<div>Hello world</div>'
      aging_work_in_progress
      cycletime_scatterplot
      @file.puts '</html>'
    end
  end

  # Return a list of [issue, x] mappings for the aging work chart
  def x_issues issues
    issues.collect do |issue|
      column_index = issue.column_times.find_index { |time| time.nil? } - 1
      [issue, (column_index * 10)]
    end
  end

  def aging_work_in_progress
    aging_issues = @all_issues.reject { |issue| issue.cycle_time }
    puts "Aging Issues: #{aging_issues.collect(&:key)}"
    puts "Aging Issues Count: #{aging_issues.size}"
    data_sets = []
    data_sets << {
      type: 'bar',
      label: '85%',
      barPercentage: 1.0,
      categoryPercentage: 1.0,
      data: [10, 20, 30, 40, 50, 80, 100]
    }
    aging_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'type' => 'scatter',
        'label' => type,
        'data' => x_issues(aging_issues)
          .select { |issue, x| issue.type == type }
          .collect do |issue,x|
            { 'y' => issue.age,
              'x' => x, # issue.cycle_start.day, # TODO: adjust to be in column
              'title' => ["#{issue.key} : #{issue.age} day#{'s' unless issue.cycle_time == 1}",issue.title]
            }
          end,
        'fill' => false,
        'showLine' => false,
        'backgroundColor' => @colours[index]
      }
    end
    @file.puts <<-END
    <h1>Aging Work in Progress</h1>
    <div>
      <canvas id="aging_work_in_progress" width="800" height="400"></canvas>
    </div>
    <script>
    new Chart(document.getElementById('aging_work_in_progress').getContext('2d'),
    {
      data: {
        datasets: #{JSON.generate(data_sets)},
        labels: [#{@column_headings.collect(&:inspect).join(',')}]
      },
      options: {
        title: {
          display: true,
          text:    "Aging work in progress"
        },
        responsive: false, // If responsive is true then it fills the screen
        scales: {
          x: {
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
    });
    </script>
    END
  end

  def cycletime_scatterplot
    completed_issues = @all_issues.select { |issue| issue.cycle_time }

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
        'backgroundColor' => @colours[index]
      }
    end
    @file.puts <<-END
    <h1>Cycletime Scatterplot</h1>
    <div>Completed work</div>
    <div>
      <canvas id="cycletime_scatterplot" width="800" height="400"></canvas>
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
    const ctx = document.getElementById('cycletime_scatterplot').getContext('2d');
    const myChart = new Chart(ctx,config);
    </script>
    END
  end

end

# ======================== #
# TODO: It's currently hardcoded to know how many columns there will be and what they'll be.
class Issue
  attr_reader :key, :title, :column_times, :type, :cycle_time, :cycle_start, :cycle_end

  def initialize row
    @key = row[0]
    @title = row[2]
    @column_times = row[3...10].collect { |time| time.nil? ? nil : DateTime.parse(time) }
    @type = row[10].inspect
    @cycle_start = @column_times[0]
    @cycle_end = @column_times[-1]
    @cycle_time = (@cycle_end - @cycle_start).to_i + 1 unless @cycle_end.nil?

    # puts '', row.inspect
    # puts @column_times.inspect
    # puts @cycle_time
  end

  def age
    (Date.today - @cycle_start).to_i + 1
  end
end

issues = []
column_headings = nil
File.foreach('target/sample-aa.csv') do |line|
  row = CSV.parse_line(line)
  if line =~ /^ID/
    column_headings = row[3...10]
    next
  end

  data = Issue.new row
  issues << data
end

HTMLReport.new.run issues: issues, column_headings: column_headings

