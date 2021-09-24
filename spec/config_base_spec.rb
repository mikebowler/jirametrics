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

    it 'throws exception when everything nil' do
      expect { ConfigBase.new file_prefix: 'foo' }.to raise_error(/Everything was nil/)
    end
  end

  context 'category_for' do
    it "where mapping doesn't exist" do 
      config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'In progress'
      config.status_category_mapping type: 'Story', status: 'Done', category: 'Done'
      expect {config.category_for type: 'Epic', status: 'Foo'}.to raise_error(/^Could not determine a category for type/)
    end

    it "where mapping does exist" do 
      config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'InProgress'
      expect(config.category_for type: 'Story', status: 'Doing').to eql 'InProgress'
    end
  end

  context "conversions" do 
    config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'

    it 'should convert string' do 
      expect(config.to_string(5)).to eql '5'
    end

    it 'should convert date with null' do 
      time = Time.now
      expect(config.to_date(time)).to eql time.to_date
    end

    it 'should convert nil to date' do 
      expect(config.to_date(nil)).to be_nil
    end
  end

  context "sort all rows" do
    it "should sort nils to the bottom" do 
      config = ConfigBase.new file_prefix: 'foo', jql: 'foo=bar'
      input = [ [nil, 1], [1, 2], [nil, 3], [4, 4] ]
      expected = [ [1, 2], [4, 4], [nil, 3], [nil, 1] ]
      expect(config.sort_output input).to eq expected
    end

  end
end