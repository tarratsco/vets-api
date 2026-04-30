# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::SubmitForm27_2008Job, type: :job do
  include Sidekiq::Testing

  before { Sidekiq::Testing.fake! }
  after  { Sidekiq::Worker.clear_all }

  let(:form_data) do
    {
      'applicantType'        => 'nextOfKin',
      'dateSigned'           => '2024-01-15',
      'certificationChecked' => true,
      'veteranInformation'   => {
        'firstName' => 'John',
        'lastName'  => 'Veteran'
      },
      'applicant' => {
        'firstName' => 'Jane',
        'lastName'  => 'Veteran',
        'zip'       => '22001'
      },
      'documents' => { 'dd214Upload' => [] },
      'metadata'  => {}
    }
  end

  let(:submission) { create(:form27_2008_submission, form_data: form_data) }

  let(:intake_upload_location_response) do
    instance_double(
      Faraday::Response,
      success?: true,
      body: { 'data' => { 'attributes' => { 'uploadUrl' => 'https://benefits-intake.va.gov/upload/abc123' } } }
    )
  end

  let(:intake_upload_response) do
    instance_double(
      Faraday::Response,
      success?: true,
      status: 200,
      body: { 'data' => { 'attributes' => { 'guid' => 'deadbeef-1234-5678-abcd-ef0123456789' } } }
    )
  end

  let(:pdf_generator)    { instance_double(Form27_2008PdfGenerator, generate: '/tmp/test_form27_2008.pdf') }
  let(:benefits_service) { instance_double(BenefitsIntakeService::Service) }

  before do
    allow(Form27_2008PdfGenerator).to receive(:new).and_return(pdf_generator)
    allow(BenefitsIntakeService::Service).to receive(:new).and_return(benefits_service)
    allow(benefits_service).to receive(:request_upload).and_return(intake_upload_location_response)
    allow(benefits_service).to receive(:upload_doc).and_return(intake_upload_response)
    allow(FileUtils).to receive(:rm_f)
    allow(File).to receive(:exist?).with('/tmp/test_form27_2008.pdf').and_return(true)
    allow(StatsD).to receive(:increment)
    allow(StatsD).to receive(:timing)
  end

  # ---------------------------------------------------------------------------
  # Job enqueueing
  # ---------------------------------------------------------------------------

  describe 'enqueueing' do
    it 'enqueues exactly one job' do
      expect do
        described_class.perform_async(submission.id)
      end.to change(described_class.jobs, :size).by(1)
    end

    it 'enqueues with the correct submission_id argument' do
      described_class.perform_async(submission.id)
      job = described_class.jobs.last
      expect(job['args']).to eq([submission.id])
    end
  end

  # ---------------------------------------------------------------------------
  # Successful perform
  # ---------------------------------------------------------------------------

  describe '#perform' do
    context 'on a successful Benefits Intake API submission' do
      it 'performs without raising an error' do
        Sidekiq::Testing.inline! do
          expect { described_class.perform_async(submission.id) }.not_to raise_error
        end
      end

      it 'marks the submission as submitted' do
        described_class.new.perform(submission.id)
        expect(submission.reload.submitted?).to be(true)
      end

      it 'sets a confirmation_number in BF-YYYYMMDD-XXXXXXXX format' do
        described_class.new.perform(submission.id)
        expect(submission.reload.confirmation_number).to match(/\ABF-\d{8}-[0-9A-F]{8}\z/)
      end

      it 'emits a StatsD success metric' do
        described_class.new.perform(submission.id)
        expect(StatsD).to have_received(:increment)
          .with("api.form27_2008.benefits_intake.success")
      end

      it 'emits a StatsD timing metric' do
        described_class.new.perform(submission.id)
        expect(StatsD).to have_received(:timing)
          .with("api.form27_2008.benefits_intake.latency", anything)
      end

      it 'generates a PDF from the form data' do
        described_class.new.perform(submission.id)
        expect(Form27_2008PdfGenerator).to have_received(:new).with(form_data)
      end

      it 'cleans up the temporary PDF file' do
        described_class.new.perform(submission.id)
        expect(FileUtils).to have_received(:rm_f).with('/tmp/test_form27_2008.pdf')
      end
    end

    context 'when the submission is already submitted' do
      before { submission.update!(submitted_at: 1.hour.ago) }

      it 'performs without error' do
        expect { described_class.new.perform(submission.id) }.not_to raise_error
      end

      it 'does not call the Benefits Intake API again' do
        described_class.new.perform(submission.id)
        expect(benefits_service).not_to have_received(:request_upload)
      end
    end

    context 'when the submission record is not found' do
      it 'raises Sidekiq::JobRetry::Skip (no retry)' do
        expect do
          described_class.new.perform(99_999_999)
        end.to raise_error(Sidekiq::JobRetry::Skip)
      end

      it 'emits a StatsD failure metric' do
        described_class.new.perform(99_999_999) rescue nil
        expect(StatsD).to have_received(:increment)
          .with("api.form27_2008.benefits_intake.failure", anything)
      end
    end

    context 'when the Benefits Intake API upload location request fails' do
      before do
        allow(intake_upload_location_response).to receive(:success?).and_return(false)
      end

      it 'raises BenefitsIntakeError' do
        expect do
          described_class.new.perform(submission.id)
        end.to raise_error(Lighthouse::SubmitForm27_2008Job::BenefitsIntakeError)
      end

      it 'emits a StatsD failure metric' do
        described_class.new.perform(submission.id) rescue nil
        expect(StatsD).to have_received(:increment)
          .with("api.form27_2008.benefits_intake.failure", anything)
      end
    end

    context 'when the Benefits Intake API upload request returns a non-success status' do
      before do
        allow(intake_upload_response).to receive(:success?).and_return(false)
        allow(intake_upload_response).to receive(:status).and_return(503)
      end

      it 'raises BenefitsIntakeError' do
        expect do
          described_class.new.perform(submission.id)
        end.to raise_error(Lighthouse::SubmitForm27_2008Job::BenefitsIntakeError)
      end
    end

    context 'with document uploads in form data' do
      let(:form_data_with_uploads) do
        form_data.deep_merge(
          'documents' => {
            'dd214Upload' => [
              { 'name' => 'DD214.pdf', 'guid' => 'abc-guid-123', 'confirmationCode' => 'code1' }
            ]
          }
        )
      end

      let(:submission_with_uploads) do
        create(:form27_2008_submission, form_data: form_data_with_uploads)
      end

      let(:mock_uploader) { instance_double(BurialFlagDocumentUploader, path: '/tmp/dd214.pdf') }

      before do
        allow(BurialFlagDocumentUploader).to receive(:new).and_return(mock_uploader)
        allow(mock_uploader).to receive(:retrieve_from_store!)
      end

      it 'retrieves staged documents by GUID' do
        described_class.new.perform(submission_with_uploads.id)
        expect(mock_uploader).to have_received(:retrieve_from_store!).with('abc-guid-123')
      end
    end

    context 'when a staged document GUID has expired' do
      let(:form_data_with_expired_upload) do
        form_data.deep_merge(
          'documents' => {
            'dd214Upload' => [
              { 'name' => 'DD214.pdf', 'guid' => 'expired-guid', 'confirmationCode' => 'code1' }
            ]
          }
        )
      end

      let(:submission_with_expired) do
        create(:form27_2008_submission, form_data: form_data_with_expired_upload)
      end

      before do
        uploader = instance_double(BurialFlagDocumentUploader)
        allow(BurialFlagDocumentUploader).to receive(:new).and_return(uploader)
        allow(uploader).to receive(:retrieve_from_store!).and_raise(CarrierWave::InvalidParameter)
      end

      it 'skips the expired document gracefully and still submits' do
        expect { described_class.new.perform(submission_with_expired.id) }.not_to raise_error
        expect(submission_with_expired.reload.submitted?).to be(true)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Sidekiq configuration
  # ---------------------------------------------------------------------------

  describe 'sidekiq configuration' do
    it 'has retry set to 5' do
      expect(described_class.sidekiq_options_hash['retry']).to eq(5)
    end

    it 'uses the default queue' do
      expect(described_class.sidekiq_options_hash['queue']).to eq('default')
    end
  end
end