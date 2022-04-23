# frozen_string_literal: true

require './spec/spec_helper'

describe IssueLink do
  let(:subject) do
    IssueLink.new origin: load_issue('SP-1'), raw: {
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

  it 'should return origin' do
    expect(subject.origin.key).to eq 'SP-1'
  end

  it 'should return other issue' do
    expect(subject.other_issue.key).to eq 'SP-12'
  end

  it 'should return direction' do
    expect(subject.direction).to be :inward
    expect(subject.inward?).to be_truthy
    expect(subject.outward?).to be_falsey
  end

  it 'should return inward label' do
    expect(subject.label).to eq 'is caused by'
  end

  it 'should return outward label' do
    subject.raw['outwardIssue'] = subject.raw['inwardIssue']
    subject.raw.delete 'inwardIssue'
    expect(subject.label).to eq 'causes'
  end
end

