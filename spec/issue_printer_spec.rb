# frozen_string_literal: true

require './spec/spec_helper'

describe IssuePrinter do
  let(:board) { sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }

  it 'prints a simple issue' do
    issue1.board.cycletime = mock_cycletime_config stub_values: [
      [issue1, nil, nil]
    ]

    expect(described_class.new(issue1).to_s).to eq <<~TEXT
      SP-1 (Story): Create new draft event
        History:
          2021-06-18 18:41:29 +0000 [priority] "Medium" (Artificial entry)
          2021-06-18 18:41:29 +0000 [  status] "Backlog":10000 (Artificial entry)
          2021-06-18 18:43:34 +0000 [  status] "Backlog":10000 -> "Selected for Development":10001 (Author: Mike Bowler)
          2021-06-18 18:44:21 +0000 [  status] "Selected for Development":10001 -> "In Progress":3 (Author: Mike Bowler)
          2021-08-29 18:04:39 +0000 [ Flagged] "Impediment" (Author: Mike Bowler)
    TEXT
  end

  it 'prints assignee and issue links' do
    issue1.board.cycletime = mock_cycletime_config stub_values: [
      [issue1, '2021-06-18T18:44:21', nil]
    ]
    fields = issue1.raw['fields']
    fields['assignee'] = { 'name' => 'Barney Rubble', 'emailAddress' => 'barney@rubble.com' }
    fields['issuelinks'] = [
      {
        'type' => { 'inward' => 'Clones' },
        'inwardIssue' => { 'key' => 'ABC123' }
      },
      {
        'type' => { 'outward' => 'Cloned by' },
        'outwardIssue' => { 'key' => 'ABC456' }
      }
    ]

    expect(described_class.new(issue1).to_s).to eq <<~TEXT
      SP-1 (Story): Create new draft event
        [assignee] "Barney Rubble" <barney@rubble.com>
        [link] Clones ABC123
        [link] Cloned by ABC456
        History:
          2021-06-18 18:41:29 +0000 [priority] "Medium" (Artificial entry)
          2021-06-18 18:41:29 +0000 [  status] "Backlog":10000 (Artificial entry)
          2021-06-18 18:43:34 +0000 [  status] "Backlog":10000 -> "Selected for Development":10001 (Author: Mike Bowler)
          2021-06-18 18:44:21 +0000 [--------] ↓↓↓↓ Started here ↓↓↓↓
          2021-06-18 18:44:21 +0000 [  status] "Selected for Development":10001 -> "In Progress":3 (Author: Mike Bowler)
          2021-08-29 18:04:39 +0000 [ Flagged] "Impediment" (Author: Mike Bowler)
    TEXT
  end
end
