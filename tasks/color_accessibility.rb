# frozen_string_literal: true

require_relative 'ciede2000'

# Measures whether a set of colours stays distinguishable to people with colour vision deficiency,
# and whether text on them is comfortable to read. Development tooling: it is not part of the gem
# (the gemspec ships lib and bin only) and nothing in the report calls it. Run `rake check_colors`.
#
# It exists because we keep getting this wrong by eye. Two facts drive the whole design:
#
# 1. Simulating the deficiency is not optional. A pair that is obvious to most people can collapse
#    entirely for someone who is not, so a palette has to be measured under simulation rather than
#    looked at. Every colour bug we have had here passed the eye test first.
# 2. Lightening a colour destroys whatever guarantee it came with. Pastel versions of a verified
#    palette are not themselves verified: lightening compresses everything toward white, which is
#    exactly what removes the separation. Measure the colours you are actually shipping.
#
# A palette is scored by its WORST pair, because that is the one somebody cannot read.
#
# Simulation is a model, not anyone's experience. Most people with colour vision deficiency are
# anomalous trichromats, seeing a compressed version rather than the flat projection simulated here,
# so a good score means "no obvious collapse" rather than "verified readable". Showing real
# before-and-after swatches to an affected reader answers in one glance what this only estimates.
module ColorAccessibility
  DEFICIENCIES = %i[normal protanopia deuteranopia].freeze

  WorstPair = Struct.new :score, :deficiency, :one, :two

  # Vienot, Brettel & Mollon 1999. These act on LINEAR rgb, not on the gamma-encoded values, which
  # is the mistake that makes a simulator quietly produce plausible but wrong colours.
  RGB_TO_LMS = [
    [17.8824, 43.5161, 4.11935],
    [3.45565, 27.1554, 3.86714],
    [0.0299566, 0.184309, 1.46709]
  ].freeze
  LMS_TO_RGB = [
    [0.0809444479, -0.130504409, 0.116721066],
    [-0.0102485335, 0.0540193266, -0.113614708],
    [-0.000365296938, -0.00412161469, 0.693511405]
  ].freeze

  D65_X = 0.95047
  D65_Z = 1.08883

  class << self
    def to_linear hex
      hex.delete('#').chars.each_slice(2).map do |pair|
        channel = pair.join.to_i(16) / 255.0
        channel <= 0.04045 ? channel / 12.92 : (((channel + 0.055) / 1.055)**2.4)
      end
    end

    def to_hex linear
      encoded = linear.map do |value|
        clamped = value.clamp 0.0, 1.0
        gamma = clamped <= 0.0031308 ? clamped * 12.92 : ((1.055 * (clamped**(1 / 2.4))) - 0.055)
        (gamma * 255).round
      end
      format '#%<red>02X%<green>02X%<blue>02X', red: encoded[0], green: encoded[1], blue: encoded[2]
    end

    def relative_luminance hex
      red, green, blue = to_linear hex
      (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    end

    def contrast_ratio one, two
      lighter, darker = [relative_luminance(one), relative_luminance(two)].minmax.reverse
      (lighter + 0.05) / (darker + 0.05)
    end

    # Which of black or white reads better on this fill, and by how much. WCAG asks 4.5:1 for
    # normal text and 7:1 for AAA. In practice 4.5 on a mid-toned fill still looks muddy, so treat
    # it as the floor rather than the target.
    def best_text_color fill
      on_black = contrast_ratio fill, '#000000'
      on_white = contrast_ratio fill, '#FFFFFF'
      on_black >= on_white ? ['black', on_black] : ['white', on_white]
    end

    def simulate hex, deficiency
      to_hex simulate_linear(to_linear(hex), deficiency)
    end

    def simulate_linear linear, deficiency
      return linear if deficiency == :normal

      long, medium, short = multiply RGB_TO_LMS, linear
      case deficiency
      when :protanopia then long = (2.02344 * medium) - (2.52581 * short)
      when :deuteranopia then medium = (0.494207 * long) + (1.24827 * short)
      else raise "Unknown deficiency: #{deficiency}"
      end
      multiply(LMS_TO_RGB, [long, medium, short]).map { |value| value.clamp 0.0, 1.0 }
    end

    def to_lab linear
      red, green, blue = linear
      x = ((0.4124564 * red) + (0.3575761 * green) + (0.1804375 * blue)) / D65_X
      y = (0.2126729 * red) + (0.7151522 * green) + (0.0721750 * blue)
      z = ((0.0193339 * red) + (0.1191920 * green) + (0.9503041 * blue)) / D65_Z
      fx, fy, fz = [x, y, z].map do |value|
        value > 0.008856 ? value**(1.0 / 3) : ((7.787 * value) + (16.0 / 116))
      end
      [(116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz)]
    end

    def ciede2000(lab_one, lab_two) = Ciede2000.between lab_one, lab_two

    # How far apart two colours look to somebody with the given deficiency. Kept in linear rgb from
    # end to end: round-tripping through 8-bit hex between the steps costs about 5%, which is enough
    # to matter when the answer is being compared against a threshold.
    def distance_under one, two, deficiency:
      ciede2000(
        to_lab(simulate_linear(to_linear(one), deficiency)),
        to_lab(simulate_linear(to_linear(two), deficiency))
      )
    end

    # A pair only has to collapse for one form of deficiency to be a problem, so the worst reading
    # is the one that counts.
    def distance one, two
      DEFICIENCIES.map { |deficiency| distance_under one, two, deficiency: deficiency }.min
    end

    def worst_pair colors
      DEFICIENCIES.flat_map do |deficiency|
        colors.combination(2).map do |one, two|
          WorstPair.new distance_under(one, two, deficiency: deficiency), deficiency, one, two
        end
      end.min_by(&:score)
    end

    private

    def multiply matrix, vector
      matrix.map { |row| row.each_with_index.sum { |value, index| value * vector[index] } }
    end
  end
end
