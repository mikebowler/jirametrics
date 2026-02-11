# frozen_string_literal: true

require 'time'

class Sprint
  attr_reader :raw

  def initialize raw:, timezone_offset:
    @raw = raw
    @timezone_offset = timezone_offset
  end

  def id = @raw['id']
  def active? = (@raw['state'] == 'active')
  def closed? = (@raw['state'] == 'closed')
  def future? = (@raw['state'] == 'future')

  def completed_at? time
    completed_at = completed_time
    completed_at && completed_at <= time
  end

  def start_time
    parse_time(@raw['activatedDate'] || @raw['startDate'])
  end

  # The time that was anticipated that the sprint would close
  def end_time
    parse_time(@raw['endDate'])
  end

  # The time that the sprint was actually closed
  def completed_time
    parse_time(@raw['completeDate'])
  end

  def goal = @raw['goal']
  def name = @raw['name']

  def day_count
    return '' if future?

    if closed?
      days = (completed_time.to_date - start_time.to_date).to_i + 1
    else
      days = (end_time.to_date - start_time.to_date).to_i + 1
    end
    "#{days} days"
  end

  private

  def parse_time time_string
    Time.parse(time_string).localtime(@timezone_offset) if time_string
  end
end
