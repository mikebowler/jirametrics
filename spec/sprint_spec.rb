# frozen_string_literal: true

require './spec/spec_helper'

describe Sprint do
  let(:sprint) do
    described_class.new(raw: {
      'id' => 1,
      'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/sprint/1',
      'state' => 'active',
      'name' => 'Scrum Sprint 1',
      'startDate' => '2022-03-26T16:04:09.679Z',
      'endDate' => '2022-04-09T16:04:00.000Z',
      'originBoardId' => 2,
      'goal' => 'Do something'
    }, timezone_offset: '+00:00')
  end

  it 'returns id' do
    expect(sprint.id).to eq 1
  end

  it 'returns state' do
    expect(sprint).to be_active
    expect(sprint).not_to be_closed
    expect(sprint).not_to be_future
  end

  it 'returns start' do
    expect(sprint.start_time).to eq Time.parse('2022-03-26T16:04:09.679Z')
  end

  it 'returns end' do
    expect(sprint.end_time).to eq Time.parse('2022-04-09T16:04:00.000Z')
  end

  it 'returns goal' do
    expect(sprint.goal).to eq 'Do something'
  end

  it 'returns day_count when active' do
    expect(sprint.day_count).to eq '15 days'
  end

  it 'returns day_count when closed' do
    sprint.raw['state'] = 'closed'
    sprint.raw['completeDate'] = '2022-03-28T16:04:00.000Z'
    expect(sprint.day_count).to eq '3 days'
  end
end
