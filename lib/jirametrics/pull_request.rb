# frozen_string_literal: true

require 'time'

class Review
  def initialize raw:
    @raw = raw
  end

  def author = @raw['author']
  def state = @raw['state']
  def submitted_at = Time.parse(@raw['submitted_at'])
end

class PullRequest
  attr_reader :raw

  def initialize raw:
    @raw = raw
  end

  def number     = @raw['number']
  def repo       = @raw['repo']
  def url        = @raw['url']
  def title      = @raw['title']
  def branch     = @raw['branch']
  def state      = @raw['state']
  def issue_keys = @raw['issue_keys']

  def opened_at = Time.parse(@raw['opened_at'])
  def closed_at = @raw['closed_at'] ? Time.parse(@raw['closed_at']) : nil
  def merged_at = @raw['merged_at'] ? Time.parse(@raw['merged_at']) : nil

  def reviews = (@raw['reviews'] || []).map { |r| Review.new(raw: r) }
end
