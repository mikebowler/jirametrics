# frozen_string_literal: true

require './spec/spec_helper'

describe SprintIssueChangeData do
  it 'returns reasonable inspect value' do
    data = described_class.new(
      time: to_time('2021-01-01'), action: :story_points, value: 5.0, issue: load_issue('SP-1'), story_points: 5.0
    )
    expect(data.inspect).to eq 'SprintIssueChangeData(@action=:story_points, @issue=Issue("SP-1"), ' \
      '@story_points=5.0, @time=2021-01-01 00:00:00 +0000, @value=5.0)'
  end
end
