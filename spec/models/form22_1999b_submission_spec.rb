# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form22_1999bSubmission, type: :model do
  subject(:submission) { build(:form22_1999b_submission) }

  # -----------------------------------------------------------------------
  # Validations
  # -----------------------------------------------------------------------
  it { is_expected.to be_valid }
  it { is_expected.to validate_presence_of(:form_data) }

  describe 'with nil form_data' do
    subject(:submission) { build(:form22_1999b_submission, form_data: nil) }

    it { is_expected.not_to be_valid }

    it 'has an error on form_data' do
      submission.valid?
      expect(submission.errors[:form_data]).to include("can't be blank")
    end
  end

  # -----------------------------------------------------------------------
  # Scopes
  # -----------------------------------------------------------------------
  describe '.pending' do
    let!(:pending_submission)   { create(:form22_1999b_submission, submitted_at: nil) }
    let!(:submitted_submission) { create(:form22_1999b_submission, :submitted) }

    it 'includes submissions without a submitted_at timestamp' do
      expect(described_class.pending).to include(pending_submission)
    end

    it 'excludes submitted submissions' do
      expect(described_class.pending).not_to include(submitted_submission)
    end
  end

  describe '.submitted' do
    let!(:pending_submission)   { create(:form22_1999b_submission, submitted_at: nil) }
    let!(:submitted_submission) { create(:form22_1999b_submission, :submitted) }

    it 'includes submitted submissions' do
      expect(described_class.submitted).to include(submitted_submission)
    end

    it 'excludes pending submissions' do
      expect(described_class.submitted).not_to include(pending_submission)
    end
  end

  # -----------------------------------------------------------------------
  # Instance methods
  # -----------------------------------------------------------------------
  describe '#mark_submitted!' do
    let(:submission) { create(:form22_1999b_submission) }
    let(:guid)       { SecureRandom.uuid }

    it 'sets submitted_at' do
      expect { submission.mark_submitted!(guid) }
        .to change { submission.reload.submitted_at }.from(nil)
    end

    it 'sets confirmation_number to the provided guid' do
      submission.mark_submitted!(guid)
      expect(submission.reload.confirmation_number).to eq(guid)
    end
  end

  describe '#parsed_form_data' do
    let(:form_data) { { 'scoCertificationAttested' => true, 'facilityCode' => '31000123' } }
    let(:submission) { build(:form22_1999b_submission, form_data: form_data.to_json) }

    it 'returns a HashWithIndifferentAccess' do
      expect(submission.parsed_form_data).to be_a(HashWithIndifferentAccess)
    end

    it 'provides access by string key' do
      expect(submission.parsed_form_data['facilityCode']).to eq('31000123')
    end

    context 'when form_data is invalid JSON' do
      let(:submission) { build(:form22_1999b_submission, form_data: '{bad json}') }

      it 'returns an empty HashWithIndifferentAccess without raising' do
        expect(submission.parsed_form_data).to eq({})
      end
    end
  end

  describe '#form_model' do
    it 'returns a SimpleFormsApi::VBA221999b instance' do
      expect(submission.form_model).to be_a(SimpleFormsApi::VBA221999b)
    end

    it 'is memoized' do
      expect(submission.form_model).to equal(submission.form_model)
    end
  end

  # -----------------------------------------------------------------------
  # Encryption
  # -----------------------------------------------------------------------
  describe 'encryption' do
    let(:raw_data) { { 'studentSsn' => '123456789' }.to_json }
    let(:saved)    { create(:form22_1999b_submission, form_data: raw_data) }

    it 'reads back the original form_data transparently' do
      expect(saved.reload.form_data).to eq(raw_data)
    end

    it 'does not store SSN in plaintext on the encrypted_form_data column' do
      # The encrypted column should not contain the raw SSN as a readable substring
      expect(saved.reload.read_attribute(:encrypted_form_data)).not_to include('123456789')
    end
  end
end