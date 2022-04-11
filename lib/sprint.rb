# frozen_string_literal: true

class Sprint
  attr_reader :raw
    
  def initialize raw:
    @raw = raw
  end

  def id = @raw['id']
  def active? = (@raw['state'] == 'active')
  def start_time = Time.parse(@raw['startDate'])

  # The time that was anticipated that the sprint would close
  def end_time = Time.parse(@raw['endDate'])

  # The time that the sprint was actually closed
  def completed_time
    Time.parse(@raw['completeDate']) if @raw['completeDate']
  end

  def goal = @raw['goal']
  def name = @raw['name']
end
