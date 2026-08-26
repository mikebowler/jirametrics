# frozen_string_literal: true

class User
  RENDERED_AVATAR_SIZE = '16x16'

  # Jira omits the user entirely when there isn't one, so callers get nil rather than a User that
  # raises on every question.
  def self.from_raw raw
    raw && new(raw: raw)
  end

  def initialize raw:
    @raw = raw
  end

  def account_id = @raw['accountId']
  def active? = @raw['active']
  def email_address = @raw['emailAddress']

  # Nil when there's no name to show, in either spelling. Callers want different things in that
  # case, so the default belongs at the call site. 'name' is what older Jira called displayName,
  # and newer versions of Cloud don't return it.
  def display_name = @raw['displayName'] || @raw['name']

  def avatar_url = @raw['avatarUrls']&.[](RENDERED_AVATAR_SIZE)
end
