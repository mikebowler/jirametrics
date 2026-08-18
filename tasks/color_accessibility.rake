# frozen_string_literal: true

require_relative 'color_accessibility'

# Reports how well the shipped palettes hold up for readers with colour vision deficiency.
#
# This reports rather than fails. A palette change is a judgement call about hue and meaning as
# much as a number, and a build that goes red because someone moved a colour by two points would
# just get ignored. Read the output and decide.
CSS_FILE = 'lib/jirametrics/html/index.css'

# The colours a reader has to tell APART from each other. Anything not in a group here is only
# ever seen on its own, where separation does not arise.
MEASURED_GROUPS = {
  'fallback palette' => /--palette-color-\d+/,
  'dependency chart fills' => /--dependency-chart-(?:story|task|bug|epic|spike)-color/
}.freeze

# Colours drawn as a filled shape with text inside them, so the text has to be readable ON the
# fill rather than against the page.
FILLED_GROUPS = ['dependency chart fills'].freeze

AA_TEXT = 4.5
AAA_TEXT = 7.0

def read_palette css, pattern
  # Only the :root block, so a dark theme override does not masquerade as an extra slot.
  root = css[/:root\s*\{(.*?)\n\}/m, 1] or raise "Could not find the :root block in #{CSS_FILE}"
  root.scan(/(#{pattern})\s*:\s*([^;]+);/).to_h { |name, value| [name, value.strip] }
end

def describe_separation label, palette
  worst = ColorAccessibility.worst_pair palette.values
  puts format('  closest pair %<score>6.2f   %<one>s and %<two>s, under %<deficiency>s', score: worst.score,
    one: palette.key(worst.one), two: palette.key(worst.two), deficiency: worst.deficiency)
  puts '  (that is the number that matters: a palette is only as readable as its closest two colours)' if
    label == MEASURED_GROUPS.keys.first
end

# Each fill declares the label colour that goes on it, so measure the pair as declared rather than
# the best available. Reporting only the best would hide the failure mode this is here to catch:
# a fill changed without its label being rechecked.
def describe_label css, fill_name, fill
  label_name = fill_name.sub(/-color$/, '-label-color')
  declared = css[/#{Regexp.escape label_name}\s*:\s*([^;]+);/, 1]&.strip
  if declared.nil?
    return format('    %<name>-38s %<fill>-7s  no %<label>s declared', name: fill_name, fill: fill,
      label: label_name)
  end

  ratio = ColorAccessibility.contrast_ratio fill, declared == 'white' ? '#FFFFFF' : '#000000'
  best, best_ratio = ColorAccessibility.best_text_color fill
  verdict =
    if ratio >= AAA_TEXT then 'comfortable'
    elsif ratio >= AA_TEXT then "passes AA but reads muddy -- #{best} would give #{format '%.2f', best_ratio}"
    else "TOO LOW -- #{best} would give #{format '%.2f', best_ratio}"
    end
  format('    %<name>-38s %<fill>-7s %<ratio>5.2f  %<verdict>s', name: fill_name, fill: fill, ratio: ratio,
    verdict: "#{declared} text, #{verdict}")
end

desc 'Report how the shipped palettes hold up for readers with colour vision deficiency'
task :check_colors do
  css = File.read CSS_FILE

  MEASURED_GROUPS.each do |label, pattern|
    palette = read_palette css, pattern
    next puts "\n#{label}: none found" if palette.empty?

    puts "\n#{label} (#{palette.size} colours)"
    describe_separation label, palette

    next unless FILLED_GROUPS.include? label

    puts '  label text as declared on each fill:'
    palette.each { |name, value| puts describe_label css, name, value }
  end

  puts "\nFor reference, the full Okabe-Ito palette measured the same way:"
  reference = ColorAccessibility.worst_pair %w[#0072B2 #E69F00 #009E73 #56B4E9 #D55E00 #CC79A7 #F0E442]
  puts format('  closest pair %<score>6.2f   %<one>s and %<two>s, under %<deficiency>s', score: reference.score,
    one: reference.one, two: reference.two, deficiency: reference.deficiency)
  puts '  Okabe-Ito is the palette these are drawn from, so its own closest pair is the practical'
  puts '  ceiling. Scoring near it means the limit is the source palette, not our choices.'
end
