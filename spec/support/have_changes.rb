# frozen_string_literal: true

# Asserts the changes on an issue, or on a collection of changes, one hash per change, using the
# same keys add_change takes.
#
#   expect(issue).to have_changes [
#     { field: 'status', value: 'In Progress', value_id: 3, time: '2024-03-01' },
#     { field: 'priority', value: 'High', old_value: 'Low' }
#   ]
#
# Preferred over comparing an array of ChangeItems, for two reasons. ChangeItem#== only looks at
# field, value and time, so a wrong value_id or old_value in an expectation is silently ignored;
# here every key you write is checked. And a failure names the change and the attribute rather than
# printing two arrays and leaving you to find the difference.
#
# Keys you leave out are not compared, so a test can say only what it cares about.
class HaveChanges
  # Every key names the method that reads it, except these two.
  READER_FOR = { artificial: :artificial?, time: :time }.freeze
  ALLOWED_KEYS = %i[field value value_id old_value old_value_id field_id artificial time].freeze

  def initialize expected
    @expected = expected
    @errors = []
  end

  # Takes an issue, or the changes themselves for subjects that expose a filtered subset such as
  # Issue#status_changes.
  def matches? issue_or_changes
    actual = issue_or_changes.respond_to?(:changes) ? issue_or_changes.changes : issue_or_changes
    if actual.size != @expected.size
      @errors << "Different number of changes. Actual: #{actual.size}, expected: #{@expected.size}"
    end

    [actual.size, @expected.size].min.times do |index|
      compare_change index: index, actual: actual[index], expected: @expected[index]
    end
    @errors.empty?
  end

  def failure_message = @errors.join("\n")

  def failure_message_when_negated = "Expected the issue not to have these changes, but it did:\n#{@expected.inspect}"

  def description = "have changes #{@expected.inspect}"

  private

  def compare_change index:, actual:, expected:
    expected.each do |key, wanted|
      raise "Unknown key #{key.inspect}. Allowed: #{ALLOWED_KEYS.inspect}" unless ALLOWED_KEYS.include?(key)

      got = actual.public_send READER_FOR.fetch(key, key)
      if key == :time
        # To the second, matching how ChangeItem itself compares times, so an expectation does not
        # have to carry the fractional part Jira happens to record.
        wanted = SpecHelpers.to_time(wanted) if wanted.is_a?(String)
        got, wanted = [got, wanted].collect { |time| time.strftime '%Y-%m-%d %H:%M:%S %z' }
      end
      next if got == wanted

      @errors << "Change #{index + 1}: #{key} is #{got.inspect}, expected #{wanted.inspect}"
    end
  end
end
