# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form27_2008Serializer, type: :serializer do
  let(:pending_submission) do
    build(:form27_2008_submission,
          submitted_at: nil,
          confirmation_number: 'BF-20240115-AABB1122')
  end

  let(:submitted_submission) do
    build(:form27_2008_submission, :submitted,
          confirmation_number: 'BF-20240115-AABB1122',
          submitted_at: Time.utc(2024, 1, 15, 12, 0, 0))
  end

  subject(:serializer) { described_class.new(pending_submission) }

  # ---------------------------------------------------------------------------
  # Key presence
  # ---------------------------------------------------------------------------

  describe 'serialized attributes' do
    let(:serialized) { serializer.serializable_hash }

    it 'includes the status key' do
      expect(serialized[:data][:attributes]).to have_key(:status)
    end

    it 'includes the confirmation_number key' do
      expect(serialized[:data][:attributes]).to have_key(:confirmation_number)
    end

    it 'includes the submitted_at key' do
      expect(serialized[:data][:attributes]).to have_key(:submitted_at)
    end
  end

  # ---------------------------------------------------------------------------
  # Pending submission values
  # ---------------------------------------------------------------------------

  describe 'for a pending submission' do
    let(:serialized) { serializer.serializable_hash[:data][:attributes] }

    it 'returns status "pending"' do
      expect(serialized[:status]).to eq('pending')
    end

    it 'returns the confirmation_number' do
      expect(serialized[:confirmation_number]).to eq('BF-20240115-AABB1122')
    end

    it 'returns nil for submitted_at' do
      expect(serialized[:submitted_at]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Submitted submission values
  # ---------------------------------------------------------------------------

  describe 'for a submitted submission' do
    subject(:serializer) { described_class.new(submitted_submission) }
    let(:serialized) { serializer.serializable_hash[:data][:attributes] }

    it 'returns status "submitted"' do
      expect(serialized[:status]).to eq('submitted')
    end

    it 'returns an ISO 8601 submitted_at timestamp' do
      expect(serialized[:submitted_at]).to eq('2024-01-15T12:00:00Z')
    end

    it 'returns the confirmation_number' do
      expect(serialized[:confirmation_number]).to eq('BF-20240115-AABB1122')
    end
  end

  # ---------------------------------------------------------------------------
  # Type
  # ---------------------------------------------------------------------------

  describe 'resource type' do
    it 'uses the correct type identifier' do
      serialized = serializer.serializable_hash
      expect(serialized[:data][:type]).to eq('form27_2008_submission')
    end
  end
end