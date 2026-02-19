# frozen_string_literal: true

class HtmlGenerator
  attr_accessor :file_system, :settings

  def create_html output_filename:, settings:
    @settings = settings
    html_directory = "#{Pathname.new(File.realpath(__FILE__)).dirname}/html"
    css = load_css html_directory: html_directory
    javascript = file_system.load(File.join(html_directory, 'index.js'))
    erb = ERB.new file_system.load(File.join(html_directory, 'index.erb'))
    file_system.save_file content: erb.result(binding), filename: output_filename
  end

  def load_css html_directory:
    base_css_filename = File.join(html_directory, 'index.css')
    base_css = file_system.load(base_css_filename)

    extra_css_filename = settings['include_css']
    if extra_css_filename
      if File.exist?(extra_css_filename)
        base_css << "\n\n" << file_system.load(extra_css_filename)
        log("Loaded CSS:  #{extra_css_filename}")
      else
        log("Unable to find specified CSS file: #{extra_css_filename}")
      end
    end

    base_css
  end
end
