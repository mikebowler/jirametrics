# frozen_string_literal: true

require 'random-word'

class Anonymizer
  def initialize issues
    @issues = issues
  end

  def run
    puts 'Anonymizing...'
    @issue_key_mapping = {}
    counter = 1

    @issues.each do |issue|
      new_key = "ANON-#{counter += 1}"
      @issue_key_mapping[issue.key] = new_key
      issue.raw['key'] = new_key
      issue.raw['fields']['summary'] = RandomWord.phrases.next.gsub(/_/, ' ')
    end
  end
end
