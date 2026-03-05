# frozen_string_literal: true

require 'time'

class PullRequestReview
  def initialize raw:
    @raw = raw
  end

  def author = @raw['author']
  def state = @raw['state']
  def submitted_at = Time.parse(@raw['submitted_at'])
end
