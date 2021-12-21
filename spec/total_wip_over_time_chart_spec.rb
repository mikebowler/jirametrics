# frozen_string_literal: true

require './spec/spec_helper'

describe TotalWipOverTimeChart do
  let(:issue1)  { load_issue 'SP-1' }
  let(:issue2)  { load_issue 'SP-2' }
  let(:issue10) { load_issue 'SP-10' }

  let :chart do
    chart = TotalWipOverTimeChart.new
    chart.cycletime = defaultCycletimeConfig
    chart
  end
end
