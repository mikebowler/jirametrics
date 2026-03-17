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

    it 'leaves color_pair nil' do
      rules.color = '#4bc14b'
      expect(rules.color_pair).to be_nil
    end

    it 'clears color_pair when reassigned from an array to a single color' do
      rules.color = ['#4bc14b', '#2a7a2a']
      rules.color = '#ff0000'
      expect(rules.color_pair).to be_nil
    end
  end

  context 'color= with a [light, dark] array' do
    it 'sets color to a CssVariable with a deterministic generated name' do
      rules.color = ['#4bc14b', '#2a7a2a']
      expect(rules.color).to be_a CssVariable
      expect(rules.color.name).to match(/^--generated-color-[0-9a-f]{8}$/)
    end

    it 'always produces the same variable name for the same pair' do
      rules.color = ['#4bc14b', '#2a7a2a']
      name1 = rules.color.name

      other = described_class.new
      other.color = ['#4bc14b', '#2a7a2a']
      expect(other.color.name).to eq name1
    end

    it 'produces different variable names for different pairs' do
      rules.color = ['#4bc14b', '#2a7a2a']
      other = described_class.new
      other.color = ['#ff0000', '#880000']
      expect(rules.color.name).not_to eq other.color.name
    end

    it 'stores the pair in color_pair' do
      rules.color = ['#4bc14b', '#2a7a2a']
      expect(rules.color_pair).to eq({ light: '#4bc14b', dark: '#2a7a2a' })
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
