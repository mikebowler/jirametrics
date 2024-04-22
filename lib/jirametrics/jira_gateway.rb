# frozen_string_literal: true

require 'cgi'
require 'json'
require 'English'

class JiraGateway
  def initialize file_system:
    @file_system = file_system
  end

  def call_command command
    @file_system.log "  #{command.gsub(/\s+/, ' ')}"
    result = `#{command}`
    @file_system.log result unless $CHILD_STATUS.success?
    return result if $CHILD_STATUS.success?

    @file_system.log "Failed call with exit status #{$CHILD_STATUS.exitstatus}. " \
      "See #{@logfile_name} for details", both: true
    exit $CHILD_STATUS.exitstatus
  end
end
