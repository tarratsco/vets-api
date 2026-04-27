# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Formva401330mSerializer, type: :serializer do
  let(:submission) do
    build(:formva40_1330m_submission,
          submission_status:   'submitted',
          confirmation_number: 'NCA-TESTCONF',
          submitted_at:        Time.utc(2026, 4, 27, 15, 52, 41))
  end

  subject(:serialized) { described_class.new(submission).as_json }

  # ---------------------------------------------------------------------------
  # Key presence
  # ---------------------------------------------------------------------------
  it 'includes the status key' do
    expect(serialized).to have_key('status')
  end

  it 'includes the confirmation_number key' do
    expect(serialized).to have_key('confirmation_number')
  end

  it 'includes the submitted_at key' do
    expect(serialized).to have_key('submitted_at')
  end

  # ---------------------------------------------------------------------------
  # Value correctness
  # ---------------------------------------------------------------------------
  it 'maps submitted status to "submitted"' do
    expect(serialized['status']).to eq('submitted')
  end

  it 'maps pending status to "received"' do
    pending_sub = build(:formva40_1330m_submission, submission_status: 'pending')
    result = described_class.new(pending_sub).as_json
    expect(result['status']).to eq('received')
  end

  it 'maps failed status to "action_required"' do
    failed_sub = build(:formva40_1330m_submission, :failed)
    result = described_class.new(failed_sub).as_json
    expect(result['status']).to eq('action_required')
  end

  it 'returns the correct confirmation_number' do
    expect(serialized['confirmation_number']).to eq('NCA-TESTCONF')
  end

  it 'returns submitted_at as an ISO 8601 string' do
    expect(serialized['submitted_at']).to eq('2026-04-27T15:52:41Z')
  end

  it 'returns nil for submitted_at when the record is still pending' do
    pending_sub = build(:formva40_1330m_submission,
                        submission_status: 'pending',
                        submitted_at:      nil)
    result = described_class.new(pending_sub).as_json
    expect(result['submitted_at']).to be_nil
  end

  it 'returns nil for confirmation_number when not yet assigned' do
    pending_sub = build(:formva40_1330m_submission,
                        submission_status:   'pending',
                        confirmation_number: nil)
    result = described_class.new(pending_sub).as_json
    expect(result['confirmation_number']).to be_nil
  end
end