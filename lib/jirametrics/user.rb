# frozen_string_literal: true

class User
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

  # What older Jira called displayName. Newer versions of Cloud don't return it.
  def name = @raw['name']

  # Nil when there's no name to show. Callers want different things in that case, so the default
  # belongs at the call site.
  def display_name = @raw['displayName']

  # 16x16 is the size the report renders avatars at.
  def avatar_url = @raw['avatarUrls']&.[]('16x16')
end
