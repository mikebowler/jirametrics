# frozen_string_literal: true

class Stitcher < HtmlGenerator
  class StitchContent
    include ValueEquality

    attr_reader :file, :title, :content, :type

    def initialize file:, title:, type:, content:
      @file = file
      @title = title
      @content = content
      @type = type
    end
  end

  attr_reader :loaded_files, :all_stitches

  def initialize file_system:
    super()
    self.file_system = file_system
    @all_stitches = []
    @loaded_files = []
  end

  def run stitch_file:
    output_filename = make_output_filename stitch_file
    file_system.log "Creating file #{output_filename.inspect}", also_write_to_stderr: true
    erb = ERB.new file_system.load(stitch_file)
    @sections = [[erb.result(binding), :body]]
    create_html output_filename: output_filename, settings: {}
  end

  def make_output_filename input_filename
    if /^(.+)\.erb$/ =~ input_filename
      "#{$1}.html"
    else
      "#{input_filename}.html"
    end
  end

  def grab_by_title title, from_file:, type: 'chart'
    parse_file from_file
    stitch_content = @all_stitches.find { |s| s.file == from_file && s.title == title && s.type == type }
    return stitch_content.content if stitch_content

    raise "Unable to find content in file #{from_file.inspect} matching title: #{title.inspect}"
  end

  def parse_file filename
    return false if @loaded_files.include? filename

    # To match: <!-- seam-start | chart78 | GithubPrScatterplot | PR Scatterplot | chart -->
    regex = /^<!-- seam-(?<seam>start|end) \| (?<id>[^|]+) \| (?<clazz>[^|]+) \| (?<title>[^|]+) \| (?<type>[^|]+) -->$/
    content = nil
    file_system.load(filename).lines do |line|
      matches = line.match(regex)
      if matches
        if matches[:seam] == 'start'
          content = +''
        else
          @all_stitches << Stitcher::StitchContent.new(
            file: filename, title: matches[:title], type: matches[:type], content: content
          )
          content = nil
        end
      elsif content
        content << line
      end
    end

    @loaded_files << filename
    true
  end
end
