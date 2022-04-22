# frozen_string_literal: true

require './spec/spec_helper'

describe LinkedIssue do
  let(:issue) do
    LinkedIssue.new raw: {
      'id' => '10019',
      'key' => 'SP-12',
      'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/issue/10019',
      'fields' => {
        'summary' => 'Report of all events',
        'status' => {
          'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/status/10002',
          'description' => '',
          'iconUrl' => 'https =>//improvingflow.atlassian.net/',
          'name' => 'Done',
          'id' => '10002',
          'statusCategory' => {
            'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/statuscategory/3',
            'id' => 3,
            'key' => 'done',
            'colorName' => 'green',
            'name' => 'Done'
          }
        },
        'priority' => {
          'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/priority/3',
          'iconUrl' => 'https =>//improvingflow.atlassian.net/images/icons/priorities/medium.svg',
          'name' => 'Medium',
          'id' => '3'
        },
        'issuetype' => {
          'self' => 'https =>//improvingflow.atlassian.net/rest/api/2/issuetype/10001',
          'id' => '10001',
          'description' => 'Functionality or a feature expressed as a user goal.',
          'iconUrl' => 'https =>//improvingflow.atlassian.net/rest/api/2/universal_avatar/view/type/issuetype/avatar/10315?size=medium',
          'name' => 'Story',
          'subtask' => false,
          'avatarId' => 10_315,
          'hierarchyLevel' => 0
        }
      }
    }

  end

  it 'gets key' do
    expect(issue.key).to eql 'SP-12'
  end

  it 'gets type' do
    expect(issue.type).to eql 'Story'
  end

  it 'gets key' do
    expect(issue.summary).to eql 'Report of all events'
  end
end

