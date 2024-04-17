# frozen_string_literal: true

require 'require_all'
require_all 'lib'

class InfoDumper
  def initialize
    @target_dir = 'target/'
  end

  def run key
    find_file_prefixes.each do |prefix|
      path = "#{@target_dir}#{prefix}_issues/#{key}.json"
      path = "#{@target_dir}#{prefix}_issues"
      Dir.foreach path do |file|
        if file =~ /^#{key}.+\.json$/
          issue = Issue.new raw: JSON.parse(File.read(File.join(path, file))), board: nil
          dump issue
        end
      end
    end
  end

  def find_file_prefixes
    prefixes = []
    Dir.foreach @target_dir do |file|
      prefixes << $1 if file =~ /^(.+)_issues$/
    end
    prefixes
  end

  def dump issue
    puts "#{issue.key} (#{issue.type}): #{compact_text issue.summary, 200}"

    assignee = issue.raw['fields']['assignee']
    puts "  [assignee] #{assignee['name'].inspect} <#{assignee['emailAddress']}>" unless assignee.nil?

    issue.raw['fields']['issuelinks'].each do |link|
      puts "  [link] #{link['type']['outward']} #{link['outwardIssue']['key']}" if link['outwardIssue']
      puts "  [link] #{link['type']['inward']} #{link['inwardIssue']['key']}" if link['inwardIssue']
    end
    issue.changes.each do |change|
      value = change.value
      old_value = change.old_value

      # Description fields get pretty verbose so reduce the clutter
      if change.field == 'description' || change.field == 'summary'
        value = compact_text value
        old_value = compact_text old_value
      end

      author = change.author
      author = "(#{author})" if author
      message = "  [change] #{change.time} [#{change.field}] "
      message << "#{compact_text(old_value).inspect} -> " unless old_value.nil? || old_value.empty?
      message << compact_text(value).inspect
      message << " #{author}" if author
      message << ' <<artificial entry>>' if change.artificial?
      puts message
    end
    puts ''
  end

  def compact_text text, max = 60
    return nil if text.nil?

    text = text.gsub(/\s+/, ' ').strip
    text = "#{text[0..max]}..." if text.length > max
    text
  end
end

if __FILE__ == $PROGRAM_NAME
  ARGV.each do |key|
    InfoDumper.new.run key
  end
end
