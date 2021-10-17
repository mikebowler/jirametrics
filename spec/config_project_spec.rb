describe ConfigProject do 
  context 'category_for' do
    it "where mapping doesn't exist" do
      config = ConfigProject.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'In progress'
      config.status_category_mapping type: 'Story', status: 'Done', category: 'Done'
      expect { config.category_for type: 'Epic', status: 'Foo', issue_id: 'SP-1' }
        .to raise_error(/^Could not determine a category for type/)
    end

    it 'where mapping does exist' do
      config = ConfigProject.new exporter: nil, target_path: nil, jira_config: nil, block: nil
      config.status_category_mapping type: 'Story', status: 'Doing', category: 'InProgress'
      expect(config.category_for(type: 'Story', status: 'Doing', issue_id: 'SP-1')).to eql 'InProgress'
    end
  end
end
