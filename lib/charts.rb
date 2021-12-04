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
      @file.puts '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>'
      # @file.puts '<script src="https://cdnjs.cloudflare.com/ajax/libs/moment.js/2.29.1/moment.min.js" integrity="sha512-qTXRIMyZIFb8iQcfjXWCO8+M5Tbc38Qi5WzdPOYZHIlZpzBHG3L3by84BBBOiRGiEb7KKtAOAs5qYdUiZiQNNQ==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>'
      # @file.puts '<script src="https://cdnjs.cloudflare.com/ajax/libs/date-fns/1.30.1/date_fns.min.js" integrity="sha512-F+u8eWHrfY8Xw9BLzZ8rG/0wIvs0y+JyRJrXjp3VjtFPylAEEGwKbua5Ip/oiVhaTDaDs4eU2Xtsxjs/9ag2bQ==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>'
      # @file.puts '<script src="https://cdn.jsdelivr.net/npm/chart.js/dist/chart.min.js"></script>'

    # @file.puts '<script src="http://cdnjs.cloudflare.com/ajax/libs/moment.js/2.13.0/moment.min.js"></script>'
    @file.puts '<script src="https://cdnjs.cloudflare.com/ajax/libs/chartjs-adapter-moment/1.0.0/chartjs-adapter-moment.js" integrity="sha512-ADAbyMMmwwyHVtg8yjnVPK2p4YyMiD3Hh05WPBm3F/F/u01dPpGPfqJaVSLHVxSXv0u+h6WRxyxDbihxLws9ig==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>'
    @file.puts '<script src="http://cdnjs.cloudflare.com/ajax/libs/jquery/2.1.3/jquery.min.js"></script>'
    @file.puts '<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/2.4.0/Chart.bundle.js"></script>'
    # @file.puts '<script src="https://cdn.jsdelivr.net/npm/chart.js@3.6.1/dist/chart.min.js"></script>'

      @file.puts '</head><body>'
      @file.puts '<div>Hello world</div>'
      scatterplot
      @file.puts '</html>'
    end
  end

  def scatterplot
    completed_issues = @all_issues.select { |issue| issue.cycle_time }

    # data = xcompleted_issues.collect do |issue|
    #   { 'y' => issue.cycle_time, 'x' => issue.column_times[-1].to_date }
    # end

    colours = %w[blue green orange yellow gray black]
    data_sets = []
    completed_issues.collect(&:type).uniq.each_with_index do |type, index|
      data_sets << {
        'label' => type,
        'data' => completed_issues
          .select { |issue| issue.type == type }
          .collect { |issue| { 'y' => issue.cycle_time, 'x' => issue.column_times[-1].to_date, 'title' => 'foo' } },
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
          xAxes: [{
            type: "time",
            time: {
                format: 'YYYY-MM-DD'
            },
            scaleLabel: {
              display: true,
              labelString: 'Date Completed'
            }
          }],
          yAxes: [{
            scaleLabel: {
              display: true,
              labelString: 'Days'
            }
          }]
        },
        plugins: {
          tooltip: {
            callbacks: {
              label: function(context) {
                return 'foo';
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
#ID,link,title,Backlog,ANALYSIS,DEFINED,DEV & PEER REVIEW,PREPARING FOR TEST,IN TEST,DONE,type,sprint_count,% blocked
class Issue
  attr_reader :key, :title, :column_times, :type, :cycle_time

  def initialize row
    @key = row[0]
    @title = row[2]
    @column_times = row[3...10].collect { |time| time.nil? ? nil : DateTime.parse(time) }
    @type = row[10].inspect
    @cycle_time = (@column_times[-1] - @column_times[0]).to_i unless @column_times[-1].nil?

    puts '', row.inspect
    puts @column_times.inspect
    puts @cycle_time
  end
end

issues = []
File.foreach('target/sample-aa.csv') do |line|
  next if line =~ /^ID/

  data = Issue.new CSV.parse_line(line)
  issues << data
end

HTMLReport.new.run issues

