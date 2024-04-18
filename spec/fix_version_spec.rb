# frozen_string_literal: true

require './spec/spec_helper'

describe FixVersion do
  let(:fix_version) { described_class.new({ 'name' => 'Barney', 'id' => '2', 'released' => true }) }

  it 'knows its name' do
    expect(fix_version.name).to eq 'Barney'
  end

  it 'knows its id' do
    expect(fix_version.id).to be 2
  end

  it 'knows if it is released' do
    expect(fix_version).to be_released
  end
end
