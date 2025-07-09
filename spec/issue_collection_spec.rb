# frozen_string_literal: true

require './spec/spec_helper'

describe IssueCollection do
  let(:issue1) { load_issue 'SP-1' }
  let(:issue2) { load_issue 'SP-2' }
  let(:with_rejected) do
    described_class.new.tap do |collection|
      collection << issue1
      collection << issue2
      collection.reject! { |issue| issue.key == 'SP-1' }
    end
  end

  it 'hides rejected issue' do
    expect(with_rejected.collect(&:key)).to eq ['SP-2']
  end

  it 'finds hidden when scanning all' do
    expect(with_rejected.find_by_key key: 'SP-1', include_hidden: true).to eq issue1
  end

  it 'does not find hidden when scanning only visible' do
    expect(with_rejected.find_by_key key: 'SP-1', include_hidden: false).to be_nil
  end
end
