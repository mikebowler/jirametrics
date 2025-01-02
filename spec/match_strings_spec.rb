# frozen_string_literal: true

require './spec/spec_helper'

describe MatchStrings do
  it 'matches nil against nil' do
    actual = nil
    expect(actual).to match_strings nil
  end

  it 'matches nil against list' do
    actual = nil
    expect(actual).not_to match_strings ['foo']
  end

  it 'matches single items' do
    actual = ['a']
    expect(actual).to match_strings ['a']
  end

  it 'gives a good error message' do
    actual = %w[one two]
    expect do
      expect(actual).to match_strings %w[one three]
    end.to raise_error 'Line 2: "three" does not match "two"'
  end
end
