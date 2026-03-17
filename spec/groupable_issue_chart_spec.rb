# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/throughput_chart'

describe GroupableIssueChart do
  it 'populates generated_colors when a color pair is used' do
    subject = ThroughputChart.new ->(_) {}
    subject.grouping_rules do |_object, rules|
      rules.label = 'Group A'
      rules.color = ['#4bc14b', '#2a7a2a']
    end
    subject.group_issues([1])
    expect(subject.generated_colors).not_to be_empty
    expect(subject.generated_colors.values.first).to eq({ light: '#4bc14b', dark: '#2a7a2a' })
  end

  it 'does not populate generated_colors for single colors' do
    subject = ThroughputChart.new ->(_) {}
    subject.grouping_rules do |_object, rules|
      rules.label = 'Group A'
      rules.color = '#4bc14b'
    end
    subject.group_issues([1])
    expect(subject.generated_colors).to be_empty
  end

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
