# frozen_string_literal: true

require './spec/spec_helper'

describe FixVersion do
  let(:subject) { FixVersion.new({ 'name' => 'Barney', 'id' => '2', 'released' => true }) }

  it 'should know its name' do
    expect(subject.name).to eq 'Barney'
  end

  it 'should know its id' do
    expect(subject.id).to be 2
  end

  it 'should know if it is released' do
    expect(subject.released?).to be_truthy
  end
end
