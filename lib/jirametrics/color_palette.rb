# frozen_string_literal: true

# Hands out colours for things that need to be told apart but where no specific colour is wanted.
# If a specific colour matters it should be configured, not obtained from here.
#
# Two properties matter and neither is obvious from the call site:
#
# 1. The colours have to stay distinguishable to people with colour vision deficiency. This started
#    life as a genuinely random picker, which regularly produced pairs nobody could tell apart, so
#    it is a curated set and must stay one. Do not "improve" it back into a generator.
# 2. It returns CssVariable rather than a literal, so the colours follow the light and dark themes
#    and can be overridden by a user's own stylesheet. Baked in hex can do neither.
#
# The number of slots is read from the CSS rather than declared here, so adding a colour is a CSS
# edit and the count never becomes something the Ruby and the CSS have to agree on separately.
class ColorPalette
  PALETTE_VARIABLE = /--palette-color-(\d+)\s*:/

  attr_reader :size

  # For anything holding a chart on its own, outside a report run: tests, and any future standalone
  # use. A report injects a shared instance so the whole page draws from one rotation, but nothing
  # depends on that, because a caller who needs a SPECIFIC colour is supposed to configure it.
  # A FRESH palette each call, not a shared singleton. The rotation is mutable state, so a memoised
  # instance would leak position between charts and, worse, between test examples. Only the parsed
  # stylesheet is cached, since that is the expensive part and it does not change.
  def self.default
    new css: shipped_css
  end

  def self.shipped_css
    @shipped_css ||= File.read File.join(__dir__, 'html', 'index.css')
  end

  def initialize css:
    @size = count_slots css
    @index = -1
  end

  # The next slot, cycling back to the first once they have all been used.
  def next_color
    @index += 1
    CssVariable["--palette-color-#{(@index % @size) + 1}"]
  end

  private

  # Only the contiguous run from 1 counts. A theme block that overrides slot 2 is not a third slot,
  # it is the cascade doing its job, so counting distinct numbers is right and counting occurrences
  # would not be. A gap ends the run because the cycle would otherwise land on a slot that no rule
  # defines, and an undefined variable resolves to nothing rather than to a colour.
  def count_slots css
    defined_slots = css.scan(PALETTE_VARIABLE).flatten.map(&:to_i).uniq
    if defined_slots.empty?
      raise 'The CSS defines no --palette-color-N variables, so there are no colours to hand out. ' \
        'They are normally defined in the :root block of jirametrics/html/index.css.'
    end

    (1..).take_while { |slot| defined_slots.include? slot }.size
  end
end
