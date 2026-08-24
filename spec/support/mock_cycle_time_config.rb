# frozen_string_literal: true

# Stubs are keyed by the issue's KEY, not by object identity. An Issue handed in is converted to its
# key straight away and the lookup takes the FIRST tuple matching that key. This is deliberate, and
# it means every issue in a test needs its own key. Build four of them as load_issue 'SP-1' and you
# have one issue wearing four hats: all four resolve to the first SP-1 stub and the other three are
# quietly discarded. Nothing raises, so the test still runs and may still pass, just against a
# fixture that says something other than what it looks like it says. Give them SP-1, SP-2, SP-3.
class MockCycleTimeConfig < CycleTimeConfig
  def initialize stub_values:
    super(possible_statuses: nil, label: nil, block: nil, settings: SpecHelpers.load_settings)

    raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

    stub_values.each { |line| normalize_stub_line line }
    @stub_values = stub_values
  end

  # Validate one [issue, start, stop] tuple and normalize it in place: issue -> key, date strings -> times.
  def normalize_stub_line line
    unless line[0].is_a?(Issue) || line[0] =~ /^[A-Z]+-\d+$/
      raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
    end

    line[0] = line[0].key if line[0].is_a?(Issue)
    line[1] = SpecHelpers.to_time(line[1]) if line[1].is_a? String
    line[2] = SpecHelpers.to_time(line[2]) if line[2].is_a? String
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
      SpecHelpers.mock_change(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time)
    end
  end
end
