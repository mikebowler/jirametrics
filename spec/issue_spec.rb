require './extract_cycle_times.rb'

def load_issue key
  Issue.new(JSON.parse(File.read("spec/#{key}.json")))
end

describe Issue do
  context "SP-1" do
    issue = load_issue 'SP-1'
    it "gets key" do
      expect(issue.key).to eql 'SP-1'
    end

    it "gets history" do
      changes = [
        ChangeItem.new({"field"=>"status", "toString"=>"In Progress"}, DateTime.parse('2021-06-18T18:44:21+00:00')),
        ChangeItem.new({"field"=>"status", "toString"=>"Selected for Development"}, DateTime.parse('2021-06-18T18:43:34+00:00'))
      ]

      expect(issue.changes).to eql changes
    end
  end
end