# frozen_string_literal: true

require './spec/spec_helper'

class TestValueEquality
  include ValueEquality

  def initialize a, b # rubocop:disable Naming/MethodParameterName
    @a = a
    @b = b
  end
end

class TestValueEqualityWithIgnore < TestValueEquality
  def value_equality_ignored_variables = [:@b]
end

describe ValueEquality do
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
