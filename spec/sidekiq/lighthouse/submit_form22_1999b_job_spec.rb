# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::SubmitForm22_1999bJob, type: :job do
  include Sidekiq::Testing

  before { Sidekiq::Testing.fake! }
  after  { Sidekiq::Testing.disable! }

  let(:form_data_hash) do
    {
      'institutionAndScoInformation' => {
        'facilityCode'    => '31000123',
        'institutionName' => 'State University of Example',
        'institutionAddress' => { 'street' => '123 University Ave', 'city' => 'Richmond', 'state' => 'VA', 'zip' => '23220' },
        'scoFirstName'    => 'Maria',
        'scoLastName'     => 'Hernandez',
        'scoPhone'        => '5558675309',
        'scoEmail'        => 'certifying.official@university.edu'
      },
      'studentAndPriorCertification' => {
        'studentFirstName'         => 'James',
        'studentLastName'          => 'Nguyen',
        'ssnOrFileNumberIndicator' => 'ssn',
        'studentSsn'               => '123456789',
        'benefitChapter'           => 'chapter_33',
        'originalCertBeginDate'    => '2024-08-19',
        'originalCertEndDate'      => '2024-12-15',
        'originalCreditHours'      => 12,
        'originalEnrollmentType'   => 'full_time'
      },
      'enrollmentChangeDetails' => {
        'typeOfChange'          => 'full_termination',
        'effectiveDateOfChange' => 10.days.ago.to_date.iso8601,
        'lastDateOfAttendance'  => 11.days.ago.to_date.iso8601,
        'reasonForChange'       => 'medical'
      },
      'scoCertificationAttested' => true
    }
  end

  let(:submission) { create(:form22_1999b_submission, form_data: form_data_hash.to_json) }
  let(:intake_guid) { SecureRandom.uuid }

  # -------------------------------------------------------------------------
  # Enqueuing
  # -------------------------------------------------------------------------
  describe '.perform_async' do
    it 'enqueues exactly one job' do
      expect {
        described_class.perform_async(submission.id)
      }.to change(described_class.jobs, :size).by(1)
    end

    it 'enqueues with the correct submission ID argument' do
      described_class.perform_async(submission.id)
      expect(described_class.jobs.last['args']).to eq([submission.id])
    end
  end

  # -------------------------------------------------------------------------
  # Perform — happy path
  # -------------------------------------------------------------------------
  describe '#perform' do
    let(:upload_location) { 'https://sandbox-api.va.gov/services/benefits-intake/v2/uploads/some-path' }
    let(:intake_service)  { instance_double(BenefitsIntake::Service) }

    before do
      allow(BenefitsIntake::Service).to receive(:new).and_return(intake_service)
      allow(intake_service).to receive(:request_upload).and_return(
        { 'location' => upload_location, 'guid' => intake_guid }
      )
      allow(intake_service).to receive(:upload_document).and_return(true)
      allow(PdfFill::Filler).to receive(:fill_form).and_return('/tmp/test_22_1999b.pdf')
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/tmp/test_22_1999b.pdf').and_return(false)
    end

    it 'performs without raising an error' do
      expect { described_class.new.perform(submission.id) }.not_to raise_error
    end

    it 'calls BenefitsIntake::Service#request_upload' do
      expect(intake_service).to receive(:request_upload).once
      described_class.new.perform(submission.id)
    end

    it 'calls BenefitsIntake::Service#upload_document' do
      expect(intake_service).to receive(:upload_document).once
      described_class.new.perform(submission.id)
    end

    it 'marks the submission as submitted with the intake GUID' do
      described_class.new.perform(submission.id)
      expect(submission.reload.confirmation_number).to eq(intake_guid)
      expect(submission.reload.submitted_at).to be_present
    end

    it 'increments the StatsD success counter' do
      expect(StatsD).to receive(:increment).with(
        "#{described_class::STATS_KEY}.attempt"
      )
      expect(StatsD).to receive(:increment).with(
        "#{described_class::STATS_KEY}.success",
        tags: anything
      )
      described_class.new.perform(submission.id)
    end
  end

  # -------------------------------------------------------------------------
  # Perform — record not found
  # -------------------------------------------------------------------------
  describe '#perform with nonexistent submission_id' do
    it 'does not raise an error' do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it 'increments the StatsD record_not_found counter' do
      expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.record_not_found")
      described_class.new.perform(999_999)
    end
  end

  # -------------------------------------------------------------------------
  # Perform — Lighthouse API failure
  # -------------------------------------------------------------------------
  describe '#perform when Lighthouse returns an error' do
    let(:intake_service) { instance_double(BenefitsIntake::Service) }

    before do
      allow(BenefitsIntake::Service).to receive(:new).and_return(intake_service)
      allow(intake_service).to receive(:request_upload).and_raise(
        StandardError, 'Lighthouse service temporarily unavailable'
      )
      allow(PdfFill::Filler).to receive(:fill_form).and_return('/tmp/test_22_1999b_err.pdf')
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/tmp/test_22_1999b_err.pdf').and_return(false)
    end

    it 'raises an error (so Sidekiq retries)' do
      expect { described_class.new.perform(submission.id) }.to raise_error(StandardError)
    end

    it 'increments the StatsD error counter' do
      expect(StatsD).to receive(:increment).with(
        "#{described_class::STATS_KEY}.error", tags: anything
      )
      described_class.new.perform(submission.id) rescue nil # rubocop:disable Style/RescueModifier
    end

    it 'reports the error to Sentry' do
      expect(Sentry).to receive(:capture_exception)
      described_class.new.perform(submission.id) rescue nil # rubocop:disable Style/RescueModifier
    end
  end

  # -------------------------------------------------------------------------
  # Sidekiq options
  # -------------------------------------------------------------------------
  describe 'sidekiq_options' do
    it 'retries 5 times' do
      expect(described_class.sidekiq_options['retry']).to eq(5)
    end
  end
end