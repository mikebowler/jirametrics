# frozen_string_literal: true

class User
  def initialize raw:
    @raw = raw
  end

  def account_id = @raw['accountId']
  def avatar_url = @raw['avatarUrls']['16x16']
  def active? = @raw['active']
  def display_name = @raw['displayName']
end
