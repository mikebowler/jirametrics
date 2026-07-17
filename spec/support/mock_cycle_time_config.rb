# frozen_string_literal: true

class MockCycleTimeConfig < CycleTimeConfig
  def initialize stub_values:
    super(possible_statuses: nil, label: nil, block: nil, settings: load_settings)

    raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

    stub_values.each do |line|
      unless line[0].is_a?(Issue) || line[0] =~ /^[A-Z]+-\d+$/
        raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
      end

      line[0] = line[0].key if line[0].is_a?(Issue)
      line[1] = to_time(line[1]) if line[1].is_a? String
      line[2] = to_time(line[2]) if line[2].is_a? String
    end
    @stub_values = stub_values
  end

  def started_stopped_changes(issue)
    value = @stub_values.find { |issue_key, _start, _stop| issue_key == issue.key }
    return [nil, nil] unless value

    [to_change(value[1]), to_change(value[2])]
  end

  def to_change change
    case change
    when nil
      nil
    when ChangeItem
      change
    else
      mock_change(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time)
    end
  end
end
