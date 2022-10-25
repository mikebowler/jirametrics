# frozen_string_literal: true

require 'time'

class IssueLink
  attr_reader :origin, :raw
  attr_writer :other_issue

  def initialize origin:, raw:
    @origin = origin
    @raw = raw
  end

  def other_issue
    @other_issue = Issue.new(raw: (inward? ? raw['inwardIssue'] : raw['outwardIssue'])) if @other_issue.nil?
    @other_issue
  end

  def direction
    # There are both just validating my assumptions of how Jira works. They'll be removed at some point if
    # I'm right that there can't be both an inward and outward in the same link.
    raise "Found both inward and outward: #{raw}" if raw['inwardIssue'] && raw['outwardIssue']
    raise "Found neither inward nor outward: #{raw}" if raw['inwardIssue'].nil? && raw['outwardIssue'].nil?

    if raw['inwardIssue']
      :inward
    else
      :outward
    end
  end

  def inward?
    direction == :inward
  end

  def outward?
    direction == :outward
  end

  def label
    if inward?
      @raw['type']['inward']
    else
      @raw['type']['outward']
    end
  end

  def name
    @raw['type']['name']
  end

  def inspect
    "IssueLink(origin=#{origin.key}, other=#{other_issue.key}, direction=#{direction}, " \
      "label=#{label.inspect}, name=#{name.inspect}"
  end
end
