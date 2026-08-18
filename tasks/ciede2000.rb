# frozen_string_literal: true

# The CIE's 2000 colour difference formula, scoring how far apart two CIE Lab colours look.
#
# Split out from ColorAccessibility because it is a published standard rather than anything we
# decided: this file is a transcription, and the policy about what score is good enough lives with
# the caller.
#
# Roughly, 1.0 is the smallest difference a person can notice under ideal conditions. It is not a
# straight distance, which is the whole point of it: the same numeric gap matters more in some
# regions of the space than others, so the formula weights lightness, chroma and hue separately
# and adds a rotation term to handle blues. dE76, which IS a straight distance, disagrees with this
# enough to change conclusions and should not be substituted for it.
#
# spec/color_accessibility_spec.rb checks this against the published Sharma, Wu & Dalal test set,
# which exists precisely because implementations disagree at the awkward points: the hue rotation
# and the discontinuity where hue wraps past 360. Do not change this file without running it.
module Ciede2000
  module_function

  def between lab_one, lab_two
    l1, a1, b1 = lab_one
    l2, a2, b2 = lab_two
    c1 = Math.sqrt((a1**2) + (b1**2))
    c2 = Math.sqrt((a2**2) + (b2**2))
    c_bar = (c1 + c2) / 2.0
    g = 0.5 * (1 - Math.sqrt((c_bar**7) / ((c_bar**7) + (25.0**7))))

    a1p = (1 + g) * a1
    a2p = (1 + g) * a2
    c1p = Math.sqrt((a1p**2) + (b1**2))
    c2p = Math.sqrt((a2p**2) + (b2**2))
    h1p = hue_angle a1p, b1
    h2p = hue_angle a2p, b2

    delta_l = l2 - l1
    delta_c = c2p - c1p
    delta_h = 2 * Math.sqrt(c1p * c2p) * Math.sin(radians(hue_difference(h1p, h2p, c1p, c2p)) / 2)

    l_bar = (l1 + l2) / 2.0
    c_bar_p = (c1p + c2p) / 2.0
    h_bar = mean_hue h1p, h2p, c1p, c2p

    t = 1 - (0.17 * Math.cos(radians(h_bar - 30))) + (0.24 * Math.cos(radians(2 * h_bar))) +
        (0.32 * Math.cos(radians((3 * h_bar) + 6))) - (0.20 * Math.cos(radians((4 * h_bar) - 63)))
    weight_l = 1 + ((0.015 * ((l_bar - 50)**2)) / Math.sqrt(20 + ((l_bar - 50)**2)))
    weight_c = 1 + (0.045 * c_bar_p)
    weight_h = 1 + (0.015 * c_bar_p * t)

    # The rotation term, which stops the formula overstating differences among saturated blues.
    rotation = -Math.sin(radians(2 * (30 * Math.exp(-(((h_bar - 275) / 25.0)**2))))) *
               (2 * Math.sqrt((c_bar_p**7) / ((c_bar_p**7) + (25.0**7))))

    Math.sqrt(((delta_l / weight_l)**2) + ((delta_c / weight_c)**2) + ((delta_h / weight_h)**2) +
      (rotation * (delta_c / weight_c) * (delta_h / weight_h)))
  end

  def radians(degrees) = degrees * Math::PI / 180

  def hue_angle a_star, b_star
    return 0.0 if a_star.zero? && b_star.zero?

    (Math.atan2(b_star, a_star) * 180 / Math::PI) % 360
  end

  # Hue is circular, so the difference has to take the short way round.
  def hue_difference h1p, h2p, c1p, c2p
    return 0 if (c1p * c2p).zero?

    difference = h2p - h1p
    return difference if difference.abs <= 180

    difference > 180 ? difference - 360 : difference + 360
  end

  def mean_hue h1p, h2p, c1p, c2p
    return h1p + h2p if (c1p * c2p).zero?
    return (h1p + h2p) / 2.0 if (h1p - h2p).abs <= 180
    return (h1p + h2p + 360) / 2.0 if h1p + h2p < 360

    (h1p + h2p - 360) / 2.0
  end
end
