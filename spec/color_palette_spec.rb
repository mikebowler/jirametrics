# frozen_string_literal: true

require './spec/spec_helper'

describe ColorPalette do
  # Slots are counted from the CSS rather than hardcoded, so that adding a colour is a CSS edit and
  # the count never becomes something callers have to agree on.
  def css_with(*slots)
    body = slots.collect { |slot| "  --palette-color-#{slot}: #000000;" }.join("\n")
    ":root {\n#{body}\n}\n"
  end

  describe '#size' do
    it 'counts the slots defined in the css' do
      expect(described_class.new(css: css_with(1, 2, 3)).size).to eq 3
    end

    # A theme block only overrides the slots it lists; anything it omits still resolves through the
    # cascade to the :root value. So an override is not an extra slot.
    it 'does not count theme overrides as additional slots' do
      css = "#{css_with 1, 2}html[data-theme=\"dark\"] {\n  --palette-color-2: #ffffff;\n}\n"
      expect(described_class.new(css: css).size).to eq 2
    end

    it 'picks up slots a user added in their own css' do
      css = "#{css_with 1, 2}\n:root {\n  --palette-color-3: #123456;\n}\n"
      expect(described_class.new(css: css).size).to eq 3
    end

    # A gap means the run stops. Slot 4 with no slot 3 would leave a hole that the cycle would land
    # on and resolve to nothing, so only the contiguous run counts.
    it 'stops at a gap rather than counting past it' do
      expect(described_class.new(css: css_with(1, 2, 4)).size).to eq 2
    end

    it 'raises when the css defines no palette at all' do
      expect { described_class.new(css: ':root { --body-background: white; }') }.to raise_error(
        /no --palette-color-N variables/
      )
    end
  end

  describe '#next_color' do
    let(:palette) { described_class.new css: css_with(1, 2, 3) }

    it 'returns a css variable rather than a literal, so it stays themeable and overridable' do
      expect(palette.next_color).to eq CssVariable['--palette-color-1']
    end

    it 'hands out a different slot each time' do
      expect([palette.next_color, palette.next_color]).to eq [
        CssVariable['--palette-color-1'], CssVariable['--palette-color-2']
      ]
    end

    it 'wraps around when it runs out' do
      4.times { palette.next_color }
      expect(palette.next_color).to eq CssVariable['--palette-color-2']
    end
  end
end
