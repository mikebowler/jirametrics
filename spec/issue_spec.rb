require './extract_cycle_times.rb'

def load_issue key
  Issue.new(JSON.parse(File.read("spec/#{key}.json")))
end

def new_change_item field:, value:, time:
  ChangeItem.new(
    { "field"=>field, "toString"=>value }, 
    DateTime.parse(time)
  )
end

describe Issue do
  it "gets key" do
    issue = load_issue 'SP-2'
    expect(issue.key).to eql 'SP-2'
  end

  it "gets simple history" do
    issue = load_issue 'SP-2'
    changes = [
      new_change_item(field: "status", value: "Selected for Development", time: '2021-06-18T18:43:38+00:00')
    ]

    expect(issue.changes).to eq changes
  end

  it "gets complex history" do 
    issue = load_issue 'SP-10'
    changes = [
      new_change_item(field: "status", value: "In Progress", time: '2021-08-29T18:06:55+00:00'),
      new_change_item(field: "priority", value: "Highest", time: '2021-08-29T18:06:43+00:00'),
      new_change_item(field: "Rank", value: "Ranked higher", time: '2021-08-29T18:06:28+00:00'),
      new_change_item(field: "status", value: "Selected for Development", time: '2021-08-29T18:06:28+00:00')
     ]
    expect(issue.changes).to eq changes
  end
end