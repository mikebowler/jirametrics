# frozen_string_literal: true

require './spec/spec_helper'

xdescribe 'ConfigBase' do
  context 'jql' do
    config = ConfigBase2.new file_prefix: 'foo', jql: ''

    it 'makes from project' do
      expect(config.make_jql(project: 'a')).to eql 'project="a"'
    end

    it 'makes from project and rolling date count' do
      today = DateTime.parse('2021-08-01')
      expected = %(project="a" AND status changed DURING ("2021-05-03 00:00","2021-08-01"))
      expect(config.make_jql(project: 'a', rolling_date_count: 90, today: today)).to eql expected
    end

    it 'makes from filter' do
      expect(config.make_jql(filter: 'a')).to eql 'filter="a"'
    end

    it 'makes from jql' do
      expect(config.make_jql(jql: 'foo=bar')).to eql 'foo=bar'
    end

    it 'throws exception when everything nil' do
      expect { config.make_jql }.to raise_error(/Everything was nil/)
    end
  end

end
