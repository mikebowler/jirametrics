# frozen_string_literal: true

require './spec/spec_helper'

describe Status do
  it 'should parse simple status from raw' do 

    status = Status.new raw: {
      "self" => "https://improvingflow.atlassian.net/rest/api/2/status/3",
      "description" => "This issue is being actively worked on at the moment by the assignee.",
      "iconUrl" => "https://improvingflow.atlassian.net/images/icons/statuses/inprogress.png",
      "name" => "InProgress",
      "untranslatedName" => "InProgress",
      "id" => "3",
      "statusCategory" => {
        "self" => "https://improvingflow.atlassian.net/rest/api/2/statuscategory/4",
        "id" => 4,
        "key" => "indeterminate",
        "colorName" => "yellow",
        "name" => "In Progress"
      }
    }
    expect(status.to_s).to eq('Status(name="InProgress", id=3, category_name="In Progress", category_id=4, project_id=)')
  end

  it 'should parse status with project id' do
    status = Status.new raw: {
      "self" => "https://improvingflow.atlassian.net/rest/api/2/status/10017",
      "description" => "",
      "iconUrl" => "https://improvingflow.atlassian.net/",
      "name" => "FakeBacklog",
      "untranslatedName" => "FakeBacklog",
      "id" => "10017",
      "statusCategory" => {
        "self" => "https://improvingflow.atlassian.net/rest/api/2/statuscategory/4",
        "id" => 4,
        "key" => "indeterminate",
        "colorName" => "yellow",
        "name" => "In Progress"
      },
      "scope" => {
        "type" => "PROJECT",
        "project" => {
          "id" => "10002"
        }
      }
    }

    expect(status.to_s).to eq(
      'Status(name="FakeBacklog", id=10017, category_name="In Progress", category_id=4, project_id=10002)'
    )

  end  
end