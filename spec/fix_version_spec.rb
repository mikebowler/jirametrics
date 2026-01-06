# frozen_string_literal: true

require './spec/spec_helper'

describe FixVersion do
  let(:fix_version) do
    described_class.new({
      'self' => 'https://improvingflow.atlassian.com/rest/api/2/version/50827',
      'id' => '2',
      'description' => 'my description',
      'name' => 'my name',
      'archived' => true,
      'released' => true,
      'releaseDate' => '2022-12-25'
      })
  end

  it 'knows its name' do
    expect(fix_version.name).to eq 'my name'
  end

  it 'knows its description' do
    expect(fix_version.description).to eq 'my description'
  end

  it 'knows its id' do
    expect(fix_version.id).to be 2
  end

  it 'knows if it is released' do
    expect(fix_version).to be_released
  end

  it 'knows if it is archived' do
    expect(fix_version).to be_archived
  end

  it 'knows release date' do
    expect(fix_version.release_date).to eq Date.parse('2022-12-25')
  end

  it 'succeeds when release date missing' do
    fix_version.raw['releaseDate'] = nil
    expect(fix_version.release_date).to be_nil
  end
end
