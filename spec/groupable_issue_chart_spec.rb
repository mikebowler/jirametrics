# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/throughput_chart'

describe GroupableIssueChart do
  it 'excludes ignored items from the input list' do
    # We need a concrete class that includes this module so we use ThroughputChart
    subject = ThroughputChart.new ->(_) {}
    subject.grouping_rules do |object, rules|
      rules.ignore if object == 2
    end
    list = [1, 2]
    subject.group_issues list
    expect(list).to eq [1]
  end
end
