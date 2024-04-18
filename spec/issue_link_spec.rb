# frozen_string_literal: true

require './spec/spec_helper'

describe IssueLink do
  let(:issue_link) do
    described_class.new origin: load_issue('SP-1'), raw: {
      'id' => '10001',
      'self' => 'https://improvingflow.atlassian.net/rest/api/2/issueLink/10001',
      'type' => {
        'id' => '10006',
        'name' => 'Problem/Incident',
        'inward' => 'is caused by',
        'outward' => 'causes',
        'self' => 'https://improvingflow.atlassian.net/rest/api/2/issueLinkType/10006'
      },
      'inwardIssue' => {
        'id' => '10019',
        'key' => 'SP-12',
        'self' => 'https://improvingflow.atlassian.net/rest/api/2/issue/10019',
        'fields' => {
          'summary' => 'Report of all events',
          'status' => {
            'self' => 'https://improvingflow.atlassian.net/rest/api/2/status/10002',
            'description' => '',
            'iconUrl' => 'https://improvingflow.atlassian.net/',
            'name' => 'Done',
            'id' => '10002',
            'statusCategory' => {
              'self' => 'https://improvingflow.atlassian.net/rest/api/2/statuscategory/3',
              'id' => 3,
              'key' => 'done',
              'colorName' => 'green',
              'name' => 'Done'
            }
          },
          'priority' => {
            'self' => 'https://improvingflow.atlassian.net/rest/api/2/priority/3',
            'iconUrl' => 'https://improvingflow.atlassian.net/images/icons/priorities/medium.svg',
            'name' => 'Medium',
            'id' => '3'
          },
          'issuetype' => {
            'self' => 'https://improvingflow.atlassian.net/rest/api/2/issuetype/10001',
            'id' => '10001',
            'description' => 'Functionality or a feature expressed as a user goal.',
            'iconUrl' => 'https://improvingflow.atlassian.net/rest/api/2/universal_avatar/view/type/issuetype/avatar/10315?size=medium',
            'name' => 'Story',
            'subtask' => false,
            'avatarId' => 10_315,
            'hierarchyLevel' => 0
          }
        }
      }
    }
  end

  it 'returns origin' do
    expect(issue_link.origin.key).to eq 'SP-1'
  end

  it 'returns other issue' do
    expect(issue_link.other_issue.key).to eq 'SP-12'
  end

  it 'returns direction' do
    expect(issue_link.direction).to be :inward
    expect(issue_link).to be_inward
    expect(issue_link).not_to be_outward
  end

  it 'returns inward label' do
    expect(issue_link.label).to eq 'is caused by'
  end

  it 'returns outward label' do
    issue_link.raw['outwardIssue'] = issue_link.raw['inwardIssue']
    issue_link.raw.delete 'inwardIssue'
    expect(issue_link.label).to eq 'causes'
  end

  it 'returns name' do
    expect(issue_link.name).to eq 'Problem/Incident'
  end
end
