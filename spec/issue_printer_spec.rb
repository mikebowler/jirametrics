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

  context 'sort_history!' do
    let(:printer) { described_class.new(issue1) }
    let(:t1) { to_time '2021-01-01' }
    let(:t2) { to_time '2021-01-02' }

    it 'sorts by time' do
      history = [[t2, 'b', 'detail2', false], [t1, 'a', 'detail1', false]]
      printer.sort_history!(history)
      expect(history.map(&:first)).to eq [t1, t2]
    end

    it 'when times are equal, sorts nil type last' do
      history = [[t1, 'status', 'detail', false], [t1, nil, 'marker', true]]
      printer.sort_history!(history)
      expect(history.map { |e| e[1] }).to eq ['status', nil]
    end

    it 'when times are equal and both have types, sorts alphabetically' do
      history = [[t1, 'status', 'detail', false], [t1, 'priority', 'detail2', false]]
      printer.sort_history!(history)
      expect(history.map { |e| e[1] }).to eq %w[priority status]
    end
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
          2021-06-18 18:44:21 +0000 [--------] vvvv Started here vvvv
          2021-06-18 18:44:21 +0000 [  status] "Selected for Development":10001 -> "In Progress":3 (Author: Mike Bowler)
          2021-08-29 18:04:39 +0000 [ Flagged] "Impediment" (Author: Mike Bowler)
    TEXT
  end
end
