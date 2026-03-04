# frozen_string_literal: true

require './spec/spec_helper'

describe PullRequest do
  let(:raw) do
    {
      'number'     => 42,
      'repo'       => 'owner/repo',
      'url'        => 'https://github.com/owner/repo/pull/42',
      'title'      => 'Fix SP-112',
      'branch'     => 'SP-112-fix',
      'state'      => 'MERGED',
      'issue_keys' => ['SP-112'],
      'opened_at'  => '2026-01-10T09:00:00Z',
      'closed_at'  => '2026-01-14T16:30:00Z',
      'merged_at'  => '2026-01-14T16:30:00Z',
      'reviews'    => [
        { 'author' => 'alice', 'state' => 'APPROVED', 'submitted_at' => '2026-01-13T10:00:00Z' }
      ]
    }
  end

  let(:pr) { described_class.new(raw: raw) }

  it 'exposes simple fields' do
    expect(pr.number).to eq 42
    expect(pr.repo).to eq 'owner/repo'
    expect(pr.url).to eq 'https://github.com/owner/repo/pull/42'
    expect(pr.title).to eq 'Fix SP-112'
    expect(pr.branch).to eq 'SP-112-fix'
    expect(pr.state).to eq 'MERGED'
    expect(pr.issue_keys).to eq ['SP-112']
  end

  it 'returns opened_at as a Time' do
    expect(pr.opened_at).to be_a Time
    expect(pr.opened_at).to eq Time.parse('2026-01-10T09:00:00Z')
  end

  it 'returns closed_at as a Time' do
    expect(pr.closed_at).to be_a Time
    expect(pr.closed_at).to eq Time.parse('2026-01-14T16:30:00Z')
  end

  it 'returns merged_at as a Time' do
    expect(pr.merged_at).to be_a Time
    expect(pr.merged_at).to eq Time.parse('2026-01-14T16:30:00Z')
  end

  it 'returns nil for closed_at when not set' do
    raw['closed_at'] = nil
    expect(pr.closed_at).to be_nil
  end

  it 'returns nil for merged_at when not set' do
    raw['merged_at'] = nil
    expect(pr.merged_at).to be_nil
  end

  it 'returns reviews as Review objects' do
    expect(pr.reviews.size).to eq 1
    expect(pr.reviews.first).to be_a Review
  end

  it 'returns empty array when no reviews' do
    raw['reviews'] = []
    expect(pr.reviews).to be_empty
  end
end

describe Review do
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
