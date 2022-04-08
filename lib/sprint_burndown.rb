# frozen_string_literal: true

class SprintBurndown < ChartBase
  attr_accessor :sprints # Do DI for this

  def run
    create_fake_sprint
    '<div>SprintBurndown goes here</div>'
  end

  def create_fake_sprint
    sprint = Sprint.new raw: {
      'id' => 1,
      'self' => 'https://improvingflow.atlassian.net/rest/agile/1.0/sprint/1',
      'state' => 'active',
      'name' => 'Scrum Sprint 1',
      'startDate' => '2022-03-26T16:04:09.679Z',
      'endDate' => '2022-04-09T16:04:00.000Z',
      'originBoardId' => 2,
      'goal' => 'Do something'
    }
    @sprints = [sprint]
  end
end
