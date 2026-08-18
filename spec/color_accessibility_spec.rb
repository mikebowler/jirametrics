# frozen_string_literal: true

require './spec/spec_helper'
require './tasks/color_accessibility'

describe ColorAccessibility do
  describe '.contrast_ratio' do
    it 'gives the maximum for black against white' do
      expect(described_class.contrast_ratio('#000000', '#FFFFFF')).to be_within(0.01).of(21.0)
    end

    it 'gives one for a colour against itself' do
      expect(described_class.contrast_ratio('#0072B2', '#0072B2')).to be_within(0.001).of(1.0)
    end

    it 'does not care which way round the pair is given' do
      expect(described_class.contrast_ratio('#0072B2', '#000000')).to(
        be_within(0.001).of(described_class.contrast_ratio('#000000', '#0072B2'))
      )
    end
  end

  # The published test set from Sharma, Wu & Dalal, which exists because the naive readings of the
  # CIEDE2000 paper disagree at exactly these points: the hue rotation term and the discontinuity
  # where hue wraps past 360. An implementation that gets these right is very unlikely to be wrong
  # anywhere else.
  describe '.ciede2000' do
    [
      [[50.0000, 2.6772, -79.7751], [50.0000, 0.0000, -82.7485], 2.0425],
      [[50.0000, -1.3802, -84.2814], [50.0000, 0.0000, -82.7485], 1.0000],
      [[50.0000, 0.0000, 0.0000], [50.0000, -1.0000, 2.0000], 2.3669],
      [[60.2574, -34.0099, 36.2677], [60.4626, -34.1751, 39.4387], 1.2644],
      [[63.0109, -31.0961, -5.8663], [62.8187, -29.7946, -4.0864], 1.2630],
      [[35.0831, -44.1164, 3.7933], [35.0232, -40.0716, 1.5901], 1.8645],
      [[22.7233, 20.0904, -46.6940], [23.0331, 14.9730, -42.5619], 2.0373],
      [[6.7747, -0.2908, -2.4247], [5.8714, -0.0985, -2.2286], 0.6377]
    ].each do |one, two, expected|
      it "scores #{one.inspect} against #{two.inspect} as #{expected}" do
        expect(described_class.ciede2000(one, two)).to be_within(0.0001).of(expected)
      end
    end

    it 'is symmetric' do
      one = [50.0, 2.6772, -79.7751]
      two = [50.0, 0.0, -82.7485]
      expect(described_class.ciede2000(one, two)).to be_within(0.0001).of(described_class.ciede2000(two, one))
    end
  end

  describe '.simulate' do
    it 'leaves a colour alone for normal vision' do
      expect(described_class.simulate('#009E73', :normal)).to eq '#009E73'
    end

    # The whole point of the exercise: a pair that is obvious to most people can collapse for
    # someone who is not, which is why measuring under simulation is the only honest check.
    it 'pulls a green and a red closer together under deuteranopia' do
      normal = described_class.distance_under '#009E73', '#D55E00', deficiency: :normal
      deuteranopia = described_class.distance_under '#009E73', '#D55E00', deficiency: :deuteranopia
      expect(deuteranopia).to be < normal
    end

    it 'barely moves a colour that sits on the confusion axis' do
      expect(described_class.simulate('#767676', :protanopia)).to eq '#767676'
    end
  end

  describe '.distance' do
    # A palette is only as good as its closest two colours, and a pair only has to collapse for one
    # form of deficiency to be a problem, so the worst reading is the one that counts.
    it 'takes the worst reading across normal vision and both dichromacies' do
      readings = %i[normal protanopia deuteranopia].collect do |deficiency|
        described_class.distance_under '#009E73', '#D55E00', deficiency: deficiency
      end
      expect(described_class.distance('#009E73', '#D55E00')).to be_within(0.0001).of(readings.min)
    end
  end

  describe '.worst_pair' do
    it 'finds the closest pair and says which deficiency brings them together' do
      # Yellow and orange are the pair that limits Okabe-Ito, and deuteranopia is what does it.
      result = described_class.worst_pair %w[#0072B2 #E69F00 #009E73 #56B4E9 #D55E00 #CC79A7 #F0E442]
      expect(result).to have_attributes(
        one: '#E69F00', two: '#F0E442', deficiency: :deuteranopia
      )
    end

    it 'reports the same score that distance gives for that pair' do
      colors = %w[#0072B2 #E69F00 #F0E442]
      result = described_class.worst_pair colors
      expect(result.score).to be_within(0.0001).of(described_class.distance(result.one, result.two))
    end
  end

  describe '.best_text_color' do
    it 'picks white when the fill is too dark for black' do
      on_white = described_class.contrast_ratio '#0072B2', '#FFFFFF'
      expect(described_class.best_text_color('#0072B2')).to eq ['white', on_white]
    end

    it 'picks black when the fill is light enough' do
      expect(described_class.best_text_color('#F0E442').first).to eq 'black'
    end
  end
end
