# frozen_string_literal: true

# Support for writing tests against jirametrics from outside this repo, for anyone building their
# own charts or other extensions.
#
# Require this and you get the whole library loaded along with it, so a client test file needs
# nothing else:
#
#   require 'jirametrics/testing'
#
# What is supported is exactly what this module holds: the Mock* classes below, plus the methods
# to_time, to_date and empty_config_block. The require above loads the rest of the library too,
# and that is a side effect of loading rather than a promise about any of it.
#
# The methods, and only the methods, arrive through include. Constants do not, because constant
# lookup in an example block runs through the block's lexical scope rather than the ancestors of
# the class it runs against:
#
#   RSpec.configure { |config| config.include JiraMetrics::Testing }
#
#   to_time '2024-01-01'                        # works, include supplies it
#   JiraMetrics::Testing::MockIssue.empty(...)  # classes are named in full
#
# Add your own alias if the full name grates. That is your namespace to spend, so we don't spend
# it for you:
#
#   MockIssue = JiraMetrics::Testing::MockIssue
#
# The require of 'jirametrics' below is not optional. This file nests inside the JiraMetrics class,
# and reopening it before Thor has defined it raises a superclass mismatch.
require 'jirametrics'
require 'require_all'
require_rel '.'

class JiraMetrics
  module Testing
    # Accepts the date formats a test is likely to write, rather than only what Time.parse takes.
    # A bare date means midnight, and a missing offset means UTC:
    #
    #   to_time '2024-01-01'                  => 2024-01-01 00:00:00 +0000
    #   to_time '2024-01-01T12:34:56'         => 2024-01-01 12:34:56 +0000
    #   to_time '2024-01-01T12:34:56.789'     => 2024-01-01 12:34:56.789 +0000
    #   to_time '2024-01-01T12:34:56 +10:00'  => 2024-01-01 12:34:56 +1000
    TIME_PATTERN = /
      ^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})
      (?<remainder>T(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})(?<fraction>\.\d+)?
      \s*(?<offset>[+-]\d{2}:?\d{2})?)?$
    /x
    private_constant :TIME_PATTERN

    extend self

    def to_time input
      return input unless input.is_a? String

      matches = input.match TIME_PATTERN
      raise "Can't parse string: #{input.inspect}" unless matches

      Time.parse format_matched_time(matches)
    end

    # The companion to to_time, for the many places a test wants a Date rather than a Time. Passes a
    # Date straight through for the same reason to_time passes a Time through.
    def to_date input
      input.is_a?(Date) ? input : Date.parse(input)
    end

    # Every chart is constructed with a configuration block, so a test that only wants to exercise
    # the chart itself still has to supply one. This is that block, doing nothing:
    #
    #   chart = MyCustomChart.new empty_config_block
    #   chart.issues = [issue]
    def empty_config_block = ->(_) {}

    private

    # Every optional part gets a default, which is what makes this long rather than interesting.
    def format_matched_time matches
      format(
        '%<year>04d-%<month>02d-%<day>02dT-%<hour>02d:%<minute>02d:%<second>02d%<fraction>s%<offset>s',
        year: matches[:year].to_i, month: matches[:month].to_i, day: matches[:day].to_i,
        hour: (matches[:hour] || 0).to_i, minute: (matches[:minute] || 0).to_i,
        second: (matches[:second] || 0).to_i,
        fraction: matches[:fraction] || '', offset: matches[:offset] || '+0000'
      )
    end
  end
end
