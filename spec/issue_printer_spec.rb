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

  context 'create_change_message' do
    let(:printer) { described_class.new(issue1) }

    it 'formats a non-status change with no prior value' do
      change = mock_change(field: 'priority', value: 'High', time: '2021-01-01', artificial: true)
      expect(printer.create_change_message(change: change, issue: issue1)).to eq '"High" (Artificial entry)'
    end

    it 'formats a non-status change with a prior value' do
      change = mock_change(field: 'priority', value: 'High', old_value: 'Low', time: '2021-01-01', artificial: true)
      expect(printer.create_change_message(change: change, issue: issue1)).to eq '"Low" -> "High" (Artificial entry)'
    end

    it 'formats a status change with value ids' do
      change = mock_change(field: 'status', value: 'In Progress', value_id: 3,
                           old_value: 'Backlog', old_value_id: 10_000, time: '2021-01-01', artificial: true)
      expect(printer.create_change_message(change: change, issue: issue1)).to eq \
        '"Backlog":10000 -> "In Progress":3 (Artificial entry)'
    end

    it 'includes the author for non-artificial changes' do
      change = mock_change(field: 'priority', value: 'High', time: '2021-01-01', artificial: false,
                           issue: issue1)
      expect(printer.create_change_message(change: change, issue: issue1)).to match(/\(Author: /)
    end

    context 'sprint changes' do
      it 'shows added sprint id when added to a new sprint' do
        change = mock_change(field: 'Sprint', value: 'Sprint 1', value_id: '10',
                             old_value: '', old_value_id: '', time: '2021-01-01', artificial: false, issue: issue1)
        expect(printer.create_change_message(change: change, issue: issue1)).to include('(added: [10])')
      end

      it 'shows removed sprint id when removed from a sprint' do
        change = mock_change(field: 'Sprint', value: '', value_id: '',
                             old_value: 'Sprint 1', old_value_id: '10', time: '2021-01-01', artificial: false,
                             issue: issue1)
        expect(printer.create_change_message(change: change, issue: issue1)).to include('(removed: [10])')
      end

      it 'shows both added and removed when moved between sprints' do
        change = mock_change(field: 'Sprint', value: 'Sprint 2', value_id: '20',
                             old_value: 'Sprint 1', old_value_id: '10', time: '2021-01-01', artificial: false,
                             issue: issue1)
        message = printer.create_change_message(change: change, issue: issue1)
        expect(message).to include('(added: [20])')
        expect(message).to include('(removed: [10])')
      end

      it 'shows no added or removed when sprint list is unchanged' do
        change = mock_change(field: 'Sprint', value: 'Sprint 1', value_id: '10',
                             old_value: 'Sprint 1', old_value_id: '10', time: '2021-01-01', artificial: false,
                             issue: issue1)
        message = printer.create_change_message(change: change, issue: issue1)
        expect(message).not_to include('added:')
        expect(message).not_to include('removed:')
      end
    end
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
