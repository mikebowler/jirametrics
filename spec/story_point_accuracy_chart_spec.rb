# frozen_string_literal: true

require './spec/spec_helper'

describe StoryPointAccuracyChart do
  let(:subject) { StoryPointAccuracyChart.new }

  context 'range_to_s' do
    it 'handles up to' do
      expect(subject.range_to_s(..5)).to eq 'Up to 5'
    end

    it 'handles or more' do
      expect(subject.range_to_s(4..)).to eq '4 or more'
    end

    it 'handles regular range' do
      expect(subject.range_to_s(1..2)).to eq '1-2'
    end

    it 'handles only one' do
      expect(subject.range_to_s(3..3)).to eq '3'
    end
  end
end
