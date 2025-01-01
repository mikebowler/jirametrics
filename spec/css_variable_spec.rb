# frozen_string_literal: true

require './spec/spec_helper'

describe CssVariable do
  it 'can inspect' do
    expect(described_class['--foo'].inspect).to eq "CssVariable['--foo']"
  end
end
