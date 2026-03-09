# frozen_string_literal: true

require 'time'
require 'jirametrics/pull_request_review'

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

  def reviews       = (@raw['reviews'] || []).map { |r| PullRequestReview.new(raw: r) }
  def additions     = @raw['additions']
  def deletions     = @raw['deletions']
  def changed_files = @raw['changed_files']
  def lines_changed = (additions || 0) + (deletions || 0)
end
