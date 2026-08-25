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
  module Testing
  end
end
