# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form22_1999bSerializer, type: :serializer do
  let(:submission) { build_stubbed(:form22_1999b_submission) }
  let(:serializer) { described_class.new(submission) }
  let(:serialized) { serializer.serializable_hash }

  describe 'serializable_hash' do
    it 'returns a hash' do
      expect(serialized).to be_a(Hash)
    end

    it 'includes a data key' do
      expect(serialized).to have_key(:data)
    end

    it 'includes attributes nested under data' do
      expect(serialized[:data]).to have_key(:attributes)
    end

    describe 'attributes' do
      subject(:attributes) { serialized[:data][:attributes] }

      it 'includes :status' do
        expect(attributes).to have_key(:status)
      end

      it 'includes :confirmation_number' do
        expect(attributes).to have_key(:confirmation_number)
      end

      it 'includes :submitted_at' do
        expect(attributes).to have_key(:submitted_at)
      end
    end
  end

  describe ':status attribute' do
    context 'when submitted_at is nil (pending)' do
      let(:submission) { build_stubbed(:form22_1999b_submission, submitted_at: nil) }

      it 'returns "pending"' do
        expect(serialized[:data][:attributes][:status]).to eq('pending')
      end
    end

    context 'when submitted_at is set' do
      let(:submission) { build_stubbed(:form22_1999b_submission, :submitted) }

      it 'returns "submitted"' do
        expect(serialized[:data][:attributes][:status]).to eq('submitted')
      end
    end
  end

  describe ':submitted_at attribute' do
    context 'when submitted_at is nil' do
      let(:submission) { build_stubbed(:form22_1999b_submission, submitted_at: nil) }

      it 'returns nil' do
        expect(serialized[:data][:attributes][:submitted_at]).to be_nil
      end
    end

    context 'when submitted_at is set' do
      let(:ts)         { Time.zone.parse('2025-06-15T14:30:00Z') }
      let(:submission) { build_stubbed(:form22_1999b_submission, submitted_at: ts) }

      it 'returns an ISO 8601 string' do
        expect(serialized[:data][:attributes][:submitted_at]).to eq('2025-06-15T14:30:00Z')
      end
    end
  end

  describe ':confirmation_number attribute' do
    context 'when confirmation_number is set' do
      let(:guid)       { SecureRandom.uuid }
      let(:submission) { build_stubbed(:form22_1999b_submission, confirmation_number: guid) }

      it 'returns the confirmation number' do
        expect(serialized[:data][:attributes][:confirmation_number]).to eq(guid)
      end
    end

    context 'when confirmation_number is nil' do
      let(:submission) { build_stubbed(:form22_1999b_submission, confirmation_number: nil) }

      it 'returns nil' do
        expect(serialized[:data][:attributes][:confirmation_number]).to be_nil
      end
    end
  end

  describe ':type' do
    it 'is set to form22_1999b_submission' do
      expect(serialized[:data][:type]).to eq(:form22_1999b_submission)
    end
  end
end