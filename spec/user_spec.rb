# frozen_string_literal: true

require './spec/spec_helper'

describe User do
  it 'parses simple status from raw' do
    user = described_class.new(raw: {
      'self' => 'https://improvingflow.atlassian.net/rest/api/2/user?accountId=712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83',
      'accountId' => '712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83',
      'accountType' => 'atlassian',
      # Deliberately one URL per size. With all four the same, this test passed whichever size
      # avatar_url reached for, so it could not have caught the icon changing size.
      'avatarUrls' => {
        '48x48' => 'https://example.com/fred-48.png',
        '24x24' => 'https://example.com/fred-24.png',
        '16x16' => 'https://example.com/fred-16.png',
        '32x32' => 'https://example.com/fred-32.png'
      },
      'displayName' => 'Fred Flintstone',
      'emailAddress' => 'fred@example.com',
      'active' => true,
      'locale' => 'en_US'
    })
    aggregate_failures do
      expect(user.account_id).to eq '712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83'
      expect(user.email_address).to eq 'fred@example.com'
      expect(user.avatar_url).to eq 'https://example.com/fred-16.png'
      expect(user).to be_active
      expect(user.display_name).to eq 'Fred Flintstone'
    end
  end

  # Not a theoretical case. Anonymizer#anonymize_author deletes avatarUrls outright
  # (anonymizer.rb:205), so any user read back from anonymized data arrives without the key.
  it 'has no avatar rather than blowing up when avatarUrls is absent' do
    user = described_class.new(raw: { 'displayName' => 'Fred Flintstone' })
    expect(user.avatar_url).to be_nil
  end

  # The shape older Jira sent: no accountId and no displayName, just the login name and an email.
  it 'falls back to the older name field, for data downloaded before accountId existed' do
    user = described_class.new(raw: { 'name' => 'fflintstone', 'emailAddress' => 'fred@example.com' })
    expect(user.display_name).to eq 'fflintstone'
  end

  it 'prefers displayName when a user carries both spellings' do
    user = described_class.new(raw: { 'displayName' => 'Fred Flintstone', 'name' => 'fflintstone' })
    expect(user.display_name).to eq 'Fred Flintstone'
  end

  describe '.from_raw' do
    # Jira leaves the whole user out when there isn't one, so every caller reading an embedded
    # user has to handle its absence. They get nil to check rather than a User that raises on
    # every question, and they each decide what an absent person should look like.
    it 'is nil when there is no user to wrap' do
      expect(described_class.from_raw(nil)).to be_nil
    end

    it 'wraps a raw user that is there' do
      expect(described_class.from_raw({ 'displayName' => 'Fred' }).display_name).to eq 'Fred'
    end
  end
end
