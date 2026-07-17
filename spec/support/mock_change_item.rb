# frozen_string_literal: true

# Builds a real ChangeItem for tests. It normalises Status arguments (pulling the name/id off the
# object) and, for status changes, validates the value/id against the board so a typo'd status or a
# missing id surfaces loudly rather than silently passing. Returned by the mock_change and
# add_mock_change spec helpers.
class MockChangeItem
  def initialize(
    field:, value:, time:, value_id: nil, old_value: nil, old_value_id: nil,
    artificial: false, issue: nil, field_id: nil
  )
    @field = field
    @value = value
    @time = time
    @value_id = value_id
    @old_value = old_value
    @old_value_id = old_value_id
    @artificial = artificial
    @issue = issue
    @field_id = field_id
  end

  def to_change_item
    normalize_status_arguments
    validate_status_change if @field == 'status' && @issue

    ChangeItem.new time: @time, artificial: @artificial, author_raw: nil, raw: {
      'field' => @field,
      'to' => @value_id,
      'toString' => @value,
      'from' => @old_value_id,
      'fromString' => @old_value,
      'fieldId' => @field_id
    }
  end

  # If either value or old_value is a Status object then pull the name and id off it.
  def normalize_status_arguments
    if @value.is_a? Status
      @value_id = @value.id
      @value = @value.name
    end
    return unless @old_value.is_a? Status

    @old_value_id = @old_value.id
    @old_value = @old_value.name
  end

  # Status names aren't unique, so a status name always has to be paired with an explicit id.
  def validate_status_change
    require_value_id!
    require_old_value_id!
    verify_value_id!
    verify_old_value_id!
  end

  def require_value_id!
    return unless @value && !@value_id

    guesses = possible_statuses.find_all_by_name(@value).collect(&:id)
    message = "ID was not specified for new status #{@value.inspect}. "
    if guesses.empty?
      message << "No statuses with name #{@value.inspect} but did find these: #{possible_statuses.inspect}"
    else
      message << "Perhaps you meant one of #{guesses.inspect}"
    end
    raise message
  end

  def require_old_value_id!
    return unless @old_value && !@old_value_id

    guesses = possible_statuses.find_all_by_name(@old_value).collect(&:id)
    raise "ID was not specified for old status #{@old_value.inspect}. Perhaps you meant one of #{guesses.inspect}"
  end

  def verify_value_id!
    return unless @value_id

    status = possible_statuses.find_by_id(@value_id)
    raise "No status found for id: #{@value_id} (#{@value.inspect}) in #{possible_statuses.inspect}" unless status
    return if status.name == @value

    raise "Value passed to mock_change (#{@value.inspect}:#{@value_id.inspect}) " \
      "doesn't match the status found in the board (#{status})"
  end

  def verify_old_value_id!
    return unless @old_value_id

    status = possible_statuses.find_by_id(@old_value_id)
    unless status
      raise "No status found for id: #{@old_value_id} (#{@old_value.inspect}) in #{possible_statuses.inspect}"
    end
    return if status.name == @old_value

    raise "Old value passed to mock_change (#{@old_value.inspect}:#{@old_value_id.inspect}) " \
      "doesn't match the status found in the board (#{status})"
  end

  def possible_statuses
    @issue.board.possible_statuses
  end
end
