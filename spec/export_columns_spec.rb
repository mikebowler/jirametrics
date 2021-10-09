require './spec/spec_helper'

class Issue
    def one config
      "one-#{config}"
    end
    def two config, arg1
      "two-#{config}"
    end
    def three arg1
      'three'
    end
end

describe ConfigBase do
  context 'method_missing' do
    issue = load_issue 'SP-2'

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

    it "should fail when calling a method that doesn't exist anywhere" do
      columns = ExportColumns.new "config"
      expect { columns.method_that_does_not_exist }.to raise_error "method_that_does_not_exist isn't a method on Issue or ExportColumns"
    end
  end
end