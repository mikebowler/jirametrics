# frozen_string_literal: true

require './spec/spec_helper'

def mock_config
  project = ConfigProject.new exporter: nil, target_path: nil, jira_config: nil, block: nil
  project.status_category_mappings['Story'] = {
    'Backlog' => 'ready',
    'Selected for Development' => 'ready',
    'In Progress' => 'in-flight',
    'Review' => 'in-flight',
    'Done' => 'finished'
  }
  file = ConfigFile.new project: project, block: nil
  ExportColumns.new file: file, block: nil
end

def mock_change field:, value:, time:
  ChangeItem.new time: time, raw: {
    'field' => field,
    'to' => 2,
    'toString' => value
  }
end

describe Issue do
  it 'gets key' do
    issue = load_issue 'SP-2'
    expect(issue.key).to eql 'SP-2'
  end

  it 'gets url' do
    issue = load_issue 'SP-2'
    expect(issue.url).to eql 'https://improvingflow.atlassian.net/browse/SP-2'
  end

  it 'gets simple history with a single status' do
    issue = load_issue 'SP-2'

    changes = [
      mock_change(field: 'status', value: 'Backlog', time: '2021-06-18T18:41:37.804+0000'),
      mock_change(field: 'status', value: 'Selected for Development', time: '2021-06-18T18:43:38+00:00')
    ]

    expect(issue.changes).to eq changes
  end

  it 'gets complex history with a mix of field types' do
    issue = load_issue 'SP-10'
    changes = [
      mock_change(field: 'status',     value: 'Backlog',                  time: '2021-06-18T18:42:52.754+0000'),
      mock_change(field: 'status',     value: 'Selected for Development', time: '2021-08-29T18:06:28+00:00'),
      mock_change(field: 'Rank',       value: 'Ranked higher',            time: '2021-08-29T18:06:28+00:00'),
      mock_change(field: 'priority',   value: 'Highest',                  time: '2021-08-29T18:06:43+00:00'),
      mock_change(field: 'status',     value: 'In Progress',              time: '2021-08-29T18:06:55+00:00'),
      mock_change(field: 'status',     value: 'Selected for Development', time: '2021-09-06T04:33:11+00:00'),
      mock_change(field: 'Flagged',    value: 'Impediment',               time: '2021-09-06T04:33:30+00:00'),
      mock_change(field: 'priority',   value: 'Medium',                   time: '2021-09-06T04:33:50+00:00'),
      mock_change(field: 'Flagged',    value: '',                         time: '2021-09-06T04:33:55+00:00'),
      mock_change(field: 'status',     value: 'In Progress',              time: '2021-09-06T04:34:02+00:00'),
      mock_change(field: 'status',     value: 'Review',                   time: '2021-09-06T04:34:21+00:00'),
      mock_change(field: 'status',     value: 'Done',                     time: '2021-09-06T04:34:26+00:00'),
      mock_change(field: 'resolution', value: 'Done',                     time: '2021-09-06T04:34:26+00:00')
     ]
    expect(issue.changes).to eq changes
  end

  it "should default the first status if there really hasn't been any yet" do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        }
      }
    }
    issue = Issue.new raw
    expect(issue.changes).to eq [
      mock_change(field: 'status', value: 'BrandNew!', time: '2021-08-29T18:00:00+00:00')
    ]
  end

  it "should give a reasonable error if the changelog isn't present" do
    raw = {  'key' => 'SP-1' }
    expect { Issue.new raw }.to raise_error(/^No changelog found in issue/)
  end

  it 'first time in status' do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('In Progress').to_s).to eql '2021-08-29T18:06:55+00:00'
  end

  it "first time in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it 'first time not in status' do
    issue = load_issue 'SP-10'
    expect(issue.first_time_not_in_status('Backlog').to_s).to eql '2021-08-29T18:06:28+00:00'
  end

  it "first time not in status where it's never in that status" do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        }
      }
    }
    issue = Issue.new raw
    expect(issue.first_time_not_in_status('BrandNew!')).to be_nil
  end

  it "first time in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it "first time for any status change - created doesn't count as status change" do
    issue = load_issue 'SP-10'
    expect(issue.first_status_change_after_created.to_s).to eql '2021-08-29T18:06:28+00:00'
  end

  it 'first time in status category' do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status_category(mock_config, 'finished').to_s).to eq '2021-09-06T04:34:26+00:00'
  end

  it 'first status change after created' do
    issue = load_issue 'SP-10'
    expect(issue.first_status_change_after_created.to_s).to eql '2021-08-29T18:06:28+00:00'
  end

  it %(first status change after created, where there isn't anything after created) do
    raw = {
      'key' => 'SP-1',
      'changelog' => { 'histories' => [] },
      'fields' => {
        'created' => '2021-08-29T18:00:00+00:00',
        'status' => {
          'name' => 'BrandNew!',
          'id' => '999'
        }
      }
    }
    issue = Issue.new raw
    expect(issue.first_status_change_after_created).to be_nil
  end

  context 'still_in_status' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status('Done')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it 'item moved to done twice should return first time only' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it "doesn't match any" do
      issue = load_issue 'SP-10'
      expect(issue.still_in_status('NoStatus')).to be_nil
    end
  end

  context 'still_in_status_category' do
    it 'item moved to done and then back to in progress' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished')).to be_nil
    end

    it 'item moved to done, back to in progress, then to done again' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it 'item moved to done twice should return first time only' do
      issue = load_issue 'SP-10'
      issue.changes << mock_change(field: 'status', value: 'In Progress', time: '2021-10-01T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-02T00:00:00+00:00')
      issue.changes << mock_change(field: 'status', value: 'Done', time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished').to_s).to eql '2021-10-02T00:00:00+00:00'
    end
  end
end
