require './spec/spec_helper'

describe ConfigBase do
  context 'method_missing' do
    issue = Object.new
    def issue.one config
      "one-#{config}"
    end
    def issue.two config, arg1
      "two-#{config}"
    end
    def issue.three arg1
      'three'
    end

    it 'should call a method with config but no args' do
      columns = ExportColumns.new "config"
      proc = columns.one

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'one-config'
    end

    it 'should call a method with config and args' do
      columns = ExportColumns.new "config"
      proc = columns.two 2

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'two-config'
    end

    it 'should call a method without config and no args' do
      columns = ExportColumns.new "config"
      proc = columns.three 3

      expect(proc).to be_a Proc
      expect(proc.call(issue)).to eql 'three'
    end
  end
end