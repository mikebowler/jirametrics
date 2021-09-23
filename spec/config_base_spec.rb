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

    context 'category_for' do
      it "where mapping doesn't exist" do 
        config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
        expect {config.category_for type: 'Epic', status: 'Foo'}.to raise_error(/^Could not determine a category for type/)
      end

      it "where mapping does exist" do 
        config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
        config.status_category_mapping type: 'Story', status: 'Doing', category: 'InProgress'
        expect(config.category_for type: 'Story', status: 'Doing').to eql 'InProgress'
      end
    end
  end
end