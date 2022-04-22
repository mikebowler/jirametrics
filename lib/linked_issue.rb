# frozen_string_literal: true

require 'time'

# Designed to be as method compatible with Issue as possible while only holding a tiny subset of the data
class LinkedIssue
  def initialize raw:
    @raw = raw
  end

  def key = @raw['key']
  def type = @raw['fields']['issuetype']['name']
  def summary = @raw['fields']['summary']
end