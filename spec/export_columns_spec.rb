# frozen_string_literal: true

require './spec/spec_helper'

class Issue
  def one config
    "one-#{config.class}"
  end

  def two config, arg1
    "two-#{config.class}-#{arg1}"
  end

  def three arg1
    "three-#{arg1}"
  end
end

describe ExportColumns do
  context 'method_missing' do
    issue = load_issue 'SP-2'
    file = ConfigFile.new project: nil, block: nil

    it 'should call a method with config but no args' do
      columns = ExportColumns.new file: file, block: nil
      proc = columns.one

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'one-ExportColumns'
    end

    it 'should call a method with config and args' do
      columns = ExportColumns.new file: file, block: nil
      proc = columns.two 2

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'two-ExportColumns-2'
    end

    it 'should call a method without config and no args' do
      columns = ExportColumns.new file: file, block: nil
      proc = columns.three 3

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'three-3'
    end

    it "should fail when calling a method that doesn't exist anywhere" do
      columns = ExportColumns.new file: file, block: nil
      expect { columns.method_that_does_not_exist }
        .to raise_error "method_that_does_not_exist isn't a method on Issue or ExportColumns"
    end
  end
end
