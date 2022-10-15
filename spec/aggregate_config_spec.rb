# frozen_string_literal: true

require './spec/spec_helper'

describe AggregateConfig do
  context 'date_range_to_time_range' do
    it '' do
      date_range = Date.parse('2022-01-01')..Date.parse('2022-01-02')
      expected = Time.parse('2022-01-01T00:00:00Z')..Time.parse('2022-01-02T23:59:59Z')
      offset = 'Z'
      subject = AggregateConfig.new project_config: nil, block: nil

      expect(subject.date_range_to_time_range(date_range: date_range, timezone_offset: offset)).to eq expected
    end
  end
end
