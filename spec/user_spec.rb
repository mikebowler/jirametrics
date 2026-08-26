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
      'active' => true,
      'locale' => 'en_US'
    })
    aggregate_failures do
      expect(user.account_id).to eq '712020:d3b13c86-3b58-4fb3-807f-e6129eb85d83'
      expect(user.avatar_url).to eq 'https://example.com/fred-16.png'
      expect(user).to be_active
      expect(user.display_name).to eq 'Fred Flintstone'
    end
  end
end
