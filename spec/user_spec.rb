# frozen_string_literal: true

require './spec/spec_helper'

describe User do
  it 'parses simple status from raw' do
    user = described_class.new(raw: {
      'self' => 'https://improvingflow.atlassian.net/rest/api/2/user?accountId=712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83',
      'accountId' => '712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83',
      'accountType' => 'atlassian',
      'avatarUrls' => {
        '48x48' => 'https://example.com/fred.png',
        '24x24' => 'https://example.com/fred.png',
        '16x16' => 'https://example.com/fred.png',
        '32x32' => 'https://example.com/fred.png'
      },
      'displayName' => 'Fred Flintstone',
      'active' => true,
      'locale' => 'en_US'
    })
    expect(user.account_id).to eq '712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83'
    expect(user.avatar_url).to eq 'https://example.com/fred.png'
    expect(user).to be_active
    expect(user.display_name).to eq 'Fred Flintstone'
  end
end
