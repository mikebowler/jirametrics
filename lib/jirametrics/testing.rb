# frozen_string_literal: true

# Support for writing tests against jirametrics from outside this repo, for anyone building their
# own charts or other extensions.
#
# Require this and you get the whole library loaded along with it, so a client test file needs
# nothing else:
#
#   require 'jirametrics/testing'
#
#   RSpec.configure { |config| config.include JiraMetrics::Testing }
#
# The require of 'jirametrics' below is not optional. This file nests inside the JiraMetrics class,
# and reopening it before Thor has defined it raises a superclass mismatch.
require 'jirametrics'
require 'require_all'
require_rel '.'

class JiraMetrics
  # Anything added here is public API and carries the usual deprecation obligations, so it is
  # deliberately empty until something has earned its place. The equivalent helpers for this
  # repo's own specs live in SpecHelpers, in spec/spec_helper.rb, where they can change freely.
  #
  # Two constraints on whatever lands here:
  #   - No dependency on RSpec, Minitest or any other test-only gem. require_rel in jirametrics.rb
  #     pulls this file into every production run, so it has to be safe to load anywhere.
  #   - No reading from spec/testdata or spec/complete_sample. That data is not packaged in the gem.
  module Testing
  end
end
