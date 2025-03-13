# frozen_string_literal: true

require './spec/spec_helper'

describe EstimationConfiguration do
  context 'estimation fields' do
    let(:board) { load_complete_sample_board }

    it 'returns default values' do
      config = board.estimation_configuration
      expect([config.display_name, config.field_id, config.units]).to eq([
        'Story Points', nil, :story_points
      ])
    end

    it 'returns for field type estimation' do
      board.raw['estimation'] = {
        'type' => 'field',
        'field' => {
          'fieldId' => 'customfield_123',
          'displayName' => 'Story-Punkte'
        }
      }

      config = board.estimation_configuration
      expect([config.display_name, config.field_id, config.units]).to eq([
        'Story-Punkte', 'customfield_123', :story_points
      ])
    end

    it 'returns seconds' do
      board.raw['estimation'] = {
        'type' => 'field',
        'field' => {
          'fieldId' => 'timeoriginalestimate',
          'displayName' => 'Original estimate'
        }
      }

      config = board.estimation_configuration
      expect([config.display_name, config.field_id, config.units]).to eq([
        'Original estimate', 'timeoriginalestimate', :seconds
      ])
    end

    it 'returns seconds' do
      board.raw['estimation'] = {
        'type' => 'issueCount'
      }

      config = board.estimation_configuration
      expect([config.display_name, config.field_id, config.units]).to eq(
        ['Issue Count', nil, :issue_count]
      )
    end
  end
end
