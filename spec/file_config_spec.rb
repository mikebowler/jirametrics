describe ConfigFile do
  context 'conversions' do
    config = ConfigFile.new project: nil, block: nil

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

  context 'sort all rows' do
    it 'should sort nils to the bottom' do
      config = ConfigFile.new project: nil, block: nil
      input = [[nil, 1], [1, 2], [nil, 3], [4, 4]]
      expected = [[1, 2], [4, 4], [nil, 3], [nil, 1]]
      expect(config.sort_output(input)).to eq expected
    end
  end
  
end