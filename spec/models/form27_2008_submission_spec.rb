# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form27_2008Submission, type: :model do
  subject { build(:form27_2008_submission) }

  # ---------------------------------------------------------------------------
  # Validity
  # ---------------------------------------------------------------------------

  it { is_expected.to be_valid }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  describe 'presence validations' do
    it { is_expected.to validate_presence_of(:form_data) }

    it 'is invalid when form_data is nil' do
      subject.form_data = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:form_data]).to include("can't be blank")
    end

    it 'is invalid when form_data is an empty string' do
      subject.form_data = ''
      expect(subject).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  describe '.pending' do
    let!(:pending_submission)   { create(:form27_2008_submission, submitted_at: nil) }
    let!(:submitted_submission) { create(:form27_2008_submission, :submitted) }

    it 'returns only submissions without submitted_at' do
      expect(described_class.pending).to include(pending_submission)
      expect(described_class.pending).not_to include(submitted_submission)
    end
  end

  describe '.submitted' do
    let!(:pending_submission)   { create(:form27_2008_submission, submitted_at: nil) }
    let!(:submitted_submission) { create(:form27_2008_submission, :submitted) }

    it 'returns only submissions with submitted_at' do
      expect(described_class.submitted).to include(submitted_submission)
      expect(described_class.submitted).not_to include(pending_submission)
    end
  end

  describe '.for_user' do
    let(:uuid) { SecureRandom.uuid }
    let!(:matching)     { create(:form27_2008_submission, user_uuid: uuid) }
    let!(:non_matching) { create(:form27_2008_submission, user_uuid: SecureRandom.uuid) }

    it 'returns submissions for the given user uuid' do
      expect(described_class.for_user(uuid)).to include(matching)
      expect(described_class.for_user(uuid)).not_to include(non_matching)
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  describe '#status' do
    it 'returns "pending" when submitted_at is nil' do
      submission = build(:form27_2008_submission, submitted_at: nil)
      expect(submission.status).to eq('pending')
    end

    it 'returns "submitted" when submitted_at is present' do
      submission = build(:form27_2008_submission, :submitted)
      expect(submission.status).to eq('submitted')
    end
  end

  describe '#submitted?' do
    it 'returns false when submitted_at is nil' do
      expect(build(:form27_2008_submission).submitted?).to be(false)
    end

    it 'returns true when submitted_at is set' do
      expect(build(:form27_2008_submission, :submitted).submitted?).to be(true)
    end
  end

  describe '#mark_submitted!' do
    let(:submission) { create(:form27_2008_submission) }

    it 'sets submitted_at to the current time' do
      freeze_time do
        submission.mark_submitted!('BF-20240115-ABCD1234')
        expect(submission.submitted_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'sets the confirmation_number' do
      submission.mark_submitted!('BF-20240115-ABCD1234')
      expect(submission.confirmation_number).to eq('BF-20240115-ABCD1234')
    end
  end

  describe '#confirmation_number' do
    it 'is auto-generated before create' do
      submission = create(:form27_2008_submission)
      expect(submission.confirmation_number).to match(/\ABF-\d{8}-[0-9A-F]{8}\z/)
    end

    it 'generates a unique number for each record' do
      first  = create(:form27_2008_submission)
      second = create(:form27_2008_submission)
      expect(first.confirmation_number).not_to eq(second.confirmation_number)
    end
  end

  # ---------------------------------------------------------------------------
  # Encryption
  # ---------------------------------------------------------------------------

  describe 'form_data encryption' do
    let(:raw_data) { { 'applicantType' => 'nextOfKin', 'certificationChecked' => true } }

    it 'stores form_data as encrypted ciphertext' do
      submission = create(:form27_2008_submission, form_data: raw_data)
      raw_record = described_class.connection.execute(
        "SELECT encrypted_form_data FROM form27_2008_submissions WHERE id = #{submission.id}"
      ).first
      expect(raw_record['encrypted_form_data']).not_to include('nextOfKin')
    end

    it 'decrypts form_data transparently on read' do
      submission = create(:form27_2008_submission, form_data: raw_data)
      reloaded   = described_class.find(submission.id)
      expect(reloaded.form_data).to include('applicantType' => 'nextOfKin')
    end
  end

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  describe 'FORM_ID' do
    it 'equals "27-2008"' do
      expect(described_class::FORM_ID).to eq('27-2008')
    end
  end
end