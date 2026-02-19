# frozen_string_literal: true

require './spec/spec_helper'

describe Stitcher do
  let(:file_system) { MockFileSystem.new }
  let(:stitcher) { described_class.new file_system: file_system }

  context 'output_filename' do
    it 'replaces erb with html' do
      expect(stitcher.make_output_filename('foo.erb')).to eq 'foo.html'
    end

    it 'appends html' do
      expect(stitcher.make_output_filename('foo')).to eq 'foo.html'
    end
  end

  context 'parse_file' do
    it 'skips if already loaded' do
      stitcher.loaded_files << 'foo.html'
      expect(stitcher.parse_file 'foo.html').to be_falsy
    end

    it 'loads file with no seams' do
      file_system.when_loading file: 'foo.html', json: 'foo'
      expect(stitcher.parse_file 'foo.html').to be_truthy
      expect(stitcher.all_stitches).to be_empty
    end

    it 'loads file with a seam' do
      file_system.when_loading file: 'foo.html', json: <<~JSON
        before
        <!-- seam-start | chart78 | CycletimeScatterplot | My title | chart -->
        during
        <!-- seam-end | chart78 | CycletimeScatterplot | My title | chart -->
        after
      JSON
      expect(stitcher.parse_file 'foo.html').to be_truthy
      expect(stitcher.all_stitches).to eq [
        Stitcher::StitchContent.new(file: 'foo.html', title: 'My title', content: "during\n", type: 'chart')
      ]
    end
  end
end
