# frozen_string_literal: true

require './spec/spec_helper'

describe IssuePrinter do
  let(:board) { sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }
  let(:printer) { described_class.new(issue1) }

  describe '#header_line' do
    it 'shows the key, type, and compacted summary' do
      expect(printer.header_line).to eq "SP-1 (Story): Create new draft event\n"
    end
  end

  describe '#assignee_line' do
    it 'is empty when there is no assignee' do
      issue1.raw['fields']['assignee'] = nil
      expect(printer.assignee_line).to eq ''
    end

    it 'shows the assignee name and email' do
      issue1.raw['fields']['assignee'] = { 'name' => 'Barney Rubble', 'emailAddress' => 'barney@rubble.com' }
      expect(printer.assignee_line).to eq %(  [assignee] "Barney Rubble" <barney@rubble.com>\n)
    end
  end

  describe '#links_section' do
    it 'is empty when there are no issue links' do
      issue1.raw['fields']['issuelinks'] = nil
      expect(printer.links_section).to eq ''
    end

    it 'renders outward and inward links and skips links with neither' do
      issue1.raw['fields']['issuelinks'] = [
        { 'type' => { 'outward' => 'Cloned by' }, 'outwardIssue' => { 'key' => 'ABC456' } },
        { 'type' => { 'inward' => 'Clones' }, 'inwardIssue' => { 'key' => 'ABC123' } },
        { 'type' => {} }
      ]
      expect(printer.links_section).to eq "  [link] Cloned by ABC456\n  [link] Clones ABC123\n"
    end
  end

  describe '#cycletime_warning' do
    it 'is empty when the board has a cycletime' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(printer.cycletime_warning).to eq ''
    end

    it 'warns when the board has no cycletime' do
      issue1.board.cycletime = nil
      expect(printer.cycletime_warning)
        .to eq "  Unable to determine start/end times as board #{issue1.board.id} has no cycletime specified\n"
    end
  end

  describe '#start_stop_entries' do
    it 'is empty when the board has no cycletime' do
      issue1.board.cycletime = nil
      expect(printer.start_stop_entries).to eq []
    end

    it 'marks both the start and finish when both are known' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-01-01'), to_time('2021-01-05')]
      ]
      expect(printer.start_stop_entries).to eq [
        [to_time('2021-01-01'), nil, 'vvvv Started here vvvv', true],
        [to_time('2021-01-05'), nil, '^^^^ Finished here ^^^^', true]
      ]
    end

    it 'omits the finish marker when there is no stop time' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2021-01-01'), nil]
      ]
      expect(printer.start_stop_entries).to eq [
        [to_time('2021-01-01'), nil, 'vvvv Started here vvvv', true]
      ]
    end

    it 'is empty when the cycletime has neither a start nor a stop time' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [[issue1, nil, nil]]
      expect(printer.start_stop_entries).to eq []
    end
  end

  describe '#discarded_change_entries' do
    it 'is empty when nothing was discarded' do
      allow(issue1).to receive(:discarded_change_times).and_return(nil)
      expect(printer.discarded_change_entries).to eq []
    end

    it 'marks each discarded change time' do
      allow(issue1).to receive(:discarded_change_times).and_return([to_time('2021-01-01'), to_time('2021-01-02')])
      expect(printer.discarded_change_entries).to eq [
        [to_time('2021-01-01'), nil, '^^^^ Changes discarded ^^^^', true],
        [to_time('2021-01-02'), nil, '^^^^ Changes discarded ^^^^', true]
      ]
    end
  end

  describe '#change_entries' do
    it 'builds an entry per change, flagging artificial vs real' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'priority', value: 'High', time: '2021-01-01', artificial: true)
      add_mock_change(issue: issue1, field: 'priority', value: 'Low', time: '2021-01-02', artificial: false)
      entries = printer.change_entries
      aggregate_failures do
        expect(entries.first).to eq [to_time('2021-01-01'), 'priority', '"High" (Artificial entry)', true]
        expect(entries.map { |entry| entry[3] }).to eq [true, false]
      end
    end

    it 'appends discarded changes after the normal ones' do
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'priority', value: 'High', time: '2021-01-01', artificial: true)
      discarded = mock_change(field: 'priority', value: 'Old', time: '2021-01-03', artificial: true)
      allow(issue1).to receive(:discarded_changes).and_return([discarded])
      expect(printer.change_entries.map { |entry| entry[0] }).to eq [to_time('2021-01-01'), to_time('2021-01-03')]
    end
  end

  describe '#build_history' do
    it 'combines start/stop, discarded, and change entries in that order' do
      issue1.board.cycletime = mock_cycletime_config stub_values: [[issue1, to_time('2021-01-01'), nil]]
      issue1.changes.clear
      add_mock_change(issue: issue1, field: 'priority', value: 'High', time: '2021-01-05', artificial: true)
      allow(issue1).to receive(:discarded_change_times).and_return([to_time('2021-01-03')])
      expect(printer.build_history.map { |entry| entry[0] }).to eq [
        to_time('2021-01-01'), to_time('2021-01-03'), to_time('2021-01-05')
      ]
    end
  end

  describe '#render_history' do
    it 'sorts, right-justifies types to the widest, and dashes nil types' do
      history = [
        [to_time('2021-01-02T00:00:00'), 'flag', 'second', false],
        [to_time('2021-01-01T00:00:00'), 'status', 'first', false],
        [to_time('2021-01-03T00:00:00'), nil, 'marker', true]
      ]
      expect(printer.render_history(history)).to eq(
        "    2021-01-01 00:00:00 +0000 [status] first\n" \
        "    2021-01-02 00:00:00 +0000 [  flag] second\n" \
        "    2021-01-03 00:00:00 +0000 [------] marker\n"
      )
    end
  end

  describe '#create_change_message' do
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
      expect(printer.create_change_message(change: change, issue: issue1)).to include('(Author: ')
    end

    context 'with sprint changes' do
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
        aggregate_failures do
          expect(message).to include('(added: [20])')
          expect(message).to include('(removed: [10])')
        end
      end

      it 'shows no added or removed when sprint list is unchanged' do
        change = mock_change(field: 'Sprint', value: 'Sprint 1', value_id: '10',
                             old_value: 'Sprint 1', old_value_id: '10', time: '2021-01-01', artificial: false,
                             issue: issue1)
        message = printer.create_change_message(change: change, issue: issue1)
        aggregate_failures do
          expect(message).not_to include('added:')
          expect(message).not_to include('removed:')
        end
      end
    end
  end

  describe '#sort_history!' do
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
