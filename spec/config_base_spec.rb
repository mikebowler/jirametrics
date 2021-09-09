require './spec/spec_helper'

describe ConfigBase do
  context 'jql' do
    it "makes from project" do
      config = ConfigBase.new file_prefix: 'foo', project: 'a'
      expect(config.jql).to eql 'project="a"'
    end

    it "makes from filter" do
      config = ConfigBase.new file_prefix: 'foo', filter: 'a'
      expect(config.jql).to eql 'filter="a"'
    end

    it "makes from jql" do
      config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
      expect(config.jql).to eql 'foo=bar'
    end

  end
end