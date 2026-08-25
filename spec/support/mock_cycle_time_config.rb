# frozen_string_literal: true

# Stubs are matched by the issue's KEY, not by object identity, so every issue in a test needs its
# own key. Build four of them as load_issue 'SP-1' and you have one issue wearing four hats. That
# used to pass quietly against whichever stub came first; it now raises.
class MockCycleTimeConfig < CycleTimeConfig
  def initialize stub_values:
    super(possible_statuses: nil, label: nil, block: nil, settings: SpecHelpers.load_settings)

    raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

    # Normalizing into a new array rather than in place. The caller may be holding this array in a
    # let or handing it to a second config, and rewriting it under them is not ours to do.
    @stub_values = stub_values.collect { |line| normalize_stub_line line }
    assert_keys_unique
  end

  def started_stopped_changes(issue)
    value = @stub_values.find { |issue_key, _start, _stop| issue_key == issue.key }
    return [nil, nil] unless value

    [to_change(value[1]), to_change(value[2])]
  end

  private

  # Returns a normalized [key, start_time, stop_time] rather than editing the caller's tuple.
  def normalize_stub_line line
    key, start, stop = line

    unless key.is_a?(Issue) || key =~ /^[A-Z]+-\d+$/
      raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
    end

    [
      key.is_a?(Issue) ? key.key : key,
      start.is_a?(String) ? SpecHelpers.to_time(start) : start,
      stop.is_a?(String) ? SpecHelpers.to_time(stop) : stop
    ]
  end

  # Only the first stub for a key is reachable, so a duplicate always means one of them is dead and
  # the test is asserting against something other than what it looks like.
  def assert_keys_unique
    duplicates = @stub_values.collect(&:first).tally.select { |_key, count| count > 1 }.keys
    return if duplicates.empty?

    raise "More than one stub for #{duplicates.sort.join(', ')}. Stubs are matched by issue key, " \
      'so only the first would ever be used. Give each issue its own key.'
  end

  def to_change change
    case change
    when nil
      nil
    when ChangeItem
      change
    else
      MockChangeItem.new(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time).to_change_item
    end
  end
end
