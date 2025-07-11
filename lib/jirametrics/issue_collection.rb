# frozen_string_literal: true

class IssueCollection < Array
  attr_reader :hidden

  def self.[] *issues
    collection = new
    issues.each { |i| collection << i }
    collection
  end

  def initialize
    super
    @hidden = []
  end

  def reject! &block
    select(&block).each do |issue|
      @hidden << issue
    end
    super
  end

  def find_by_key key:, include_hidden: false
    block = ->(issue) { issue.key == key }
    issue = find(&block)
    issue = hidden.find(&block) if issue.nil? && include_hidden
    issue
  end
  def clone
    raise 'baboom'
  end
end
