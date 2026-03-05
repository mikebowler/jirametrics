# frozen_string_literal: true

require './spec/spec_helper'

describe PullRequestReview do
  let(:raw) { { 'author' => 'alice', 'state' => 'APPROVED', 'submitted_at' => '2026-01-13T10:00:00Z' } }
  let(:review) { described_class.new(raw: raw) }

  it 'exposes author and state' do
    expect(review.author).to eq 'alice'
    expect(review.state).to eq 'APPROVED'
  end

  it 'returns submitted_at as a Time' do
    expect(review.submitted_at).to be_a Time
    expect(review.submitted_at).to eq Time.parse('2026-01-13T10:00:00Z')
  end
end
