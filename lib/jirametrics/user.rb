# frozen_string_literal: true

class User
  # Jira omits the whole user object when there isn't one, so callers reading an embedded user get
  # nil to check rather than a User that raises on every question.
  def self.from_raw raw
    raw && new(raw: raw)
  end

  def initialize raw:
    @raw = raw
  end

  def account_id = @raw['accountId']
  def active? = @raw['active']

  # The honest answer, including nil. Callers each want something different when there is no name
  # to show: Issue#author wants '', ChangeItem#author wants 'Unknown author', and Issue#assigned_to
  # wants the nil so it can tell unassigned from unnameable. So the default belongs at the call
  # site, where you can see which one you're getting.
  def display_name = @raw['displayName']

  # 16x16 because that is the size the report renders these at, sized to 1em by the .icon rule.
  # avatarUrls can be absent entirely: Anonymizer#anonymize_author deletes it.
  def avatar_url = @raw['avatarUrls']&.[]('16x16')
end
