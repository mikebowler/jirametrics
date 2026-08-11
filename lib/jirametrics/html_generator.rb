# frozen_string_literal: true

class HtmlGenerator
  attr_accessor :file_system, :settings

  def create_html output_filename:, settings:, project_name: ''
    @settings = settings
    project_name = project_name.to_s
    css = load_css html_directory: html_directory
    javascript = file_system.load(File.join(html_directory, 'index.js'))
    erb = ERB.new file_system.load(File.join(html_directory, 'index.erb'))
    file_system.save_file content: erb.result(binding), filename: output_filename
  end

  # Charts allocate colours while they run, which happens before create_html is reached, so the
  # palette cannot wait for the CSS that create_html loads. It reads the files directly instead.
  # Deliberately not going through file_system: the shipped stylesheet is part of the gem rather
  # than user data, and the palette only needs to count slots in it.
  def color_palette
    @color_palette ||= ColorPalette.new css: palette_css
  end

  def palette_css
    base = File.read File.join(html_directory, 'index.css')
    extra = settings && settings['include_css']
    return base unless extra && File.exist?(extra)

    "#{base}\n\n#{File.read extra}"
  end

  def html_directory
    "#{Pathname.new(File.realpath(__FILE__)).dirname}/html"
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
