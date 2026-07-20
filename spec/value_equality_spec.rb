# frozen_string_literal: true

require './spec/spec_helper'

describe ValueEquality do
  # TestValueEquality (+ WithIgnore subclass) are single-use fixtures for the ValueEquality mixin.
  # stub_const scopes them to these examples rather than leaking classes into the global namespace.
  before do
    stub_const('TestValueEquality', Class.new do
      include ValueEquality

      def initialize first, second
        @first = first
        @second = second
      end
    end)

    stub_const('TestValueEqualityWithIgnore', Class.new(TestValueEquality) do
      def value_equality_ignored_variables = [:@second]
    end)
  end

  it 'Includes all variables' do
    expect(TestValueEquality.new(1, 2)).not_to eq TestValueEquality.new(1, 3)
  end

  it 'Ignores second variable' do
    expect(TestValueEqualityWithIgnore.new(1, 2)).to eq TestValueEqualityWithIgnore.new(1, 3)
  end

  it 'returns false if objects are different types' do
    expect(TestValueEquality.new(1, 2)).not_to eq 'foo'
  end
end
