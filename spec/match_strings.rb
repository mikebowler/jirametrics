# frozen_string_literal: true

class MatchStrings
  def initialize expected
    @expected = expected
    @errors = []
  end

  # def description
  #   'be a URL'
  # end

  def matches?(actual)
    return @expected.nil? if actual.nil?

    unless actual.size == @expected.size
      @errors << "Different numbers of lines. Actual: #{actual.size}, expected: #{@expected.size}"
    end

    biggest_size = [actual.size, @expected.size].min
    (0..biggest_size).each do |i|
      unless @expected[i] === actual[i] # rubocop:disable Style/CaseEquality
        @errors << "Line #{i + 1}: #{@expected[i].inspect} does not match #{actual[i].inspect}"
      end
    end
    @errors.empty?
  end

  def failure_message
    @errors.join("\n")
  end
end
