# frozen_string_literal: true

require './spec/spec_helper'

describe GroupingRules do
  subject(:rules) { described_class.new }

  context 'color= with a single color' do
    it 'accepts a hex string' do
      rules.color = '#4bc14b'
      expect(rules.color).to eq '#4bc14b'
    end

    it 'accepts a css variable string' do
      rules.color = '--type-story-color'
      expect(rules.color).to eq CssVariable['--type-story-color']
    end
  end

  context 'color= with a [light, dark] array' do
    it 'sets color to a RawJavascript' do
      rules.color = ['#4bc14b', '#2a7a2a']
      expect(rules.color).to be_a RawJavascript
    end

    it 'always produces the same RawJavascript for the same pair' do
      rules.color = ['#4bc14b', '#2a7a2a']
      js1 = rules.color.to_json

      other = described_class.new
      other.color = ['#4bc14b', '#2a7a2a']
      expect(other.color.to_json).to eq js1
    end

    it 'produces different RawJavascripts for different pairs' do
      rules.color = ['#4bc14b', '#2a7a2a']
      other = described_class.new
      other.color = ['#ff0000', '#880000']
      expect(rules.color.to_json).not_to eq other.color.to_json
    end

    it 'two rules with the same pair are eql?' do
      rules.label = 'Story'
      rules.color = ['#4bc14b', '#2a7a2a']
      other = described_class.new
      other.label = 'Story'
      other.color = ['#4bc14b', '#2a7a2a']
      expect(rules).to eql(other)
    end

    it 'raises ArgumentError when array does not have exactly two elements' do
      expect { rules.color = ['#4bc14b'] }.to raise_error(
        ArgumentError, 'Color pair must have exactly two elements: [light_color, dark_color]'
      )
    end

    it 'raises ArgumentError when array contains a non-string element' do
      expect { rules.color = ['#4bc14b', 123] }.to raise_error(
        ArgumentError, 'Color pair elements must be strings'
      )
    end

    it 'raises ArgumentError when array contains a css variable reference' do
      expect { rules.color = ['#4bc14b', '--some-var'] }.to raise_error(
        ArgumentError,
        'CSS variable references are not supported as color pair elements; use a literal color value instead'
      )
    end
  end
end
