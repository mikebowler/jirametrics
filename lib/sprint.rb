# frozen_string_literal: true

class Sprint
  def initialize raw:
    @raw = raw
  end

  def id = @raw['id']
  def active? = (@raw['state'] == 'active')
  def start_time = DateTime.parse(@raw['startDate'])
  def end_time = DateTime.parse(@raw['endDate'])
  def goal = @raw['goal']
end
