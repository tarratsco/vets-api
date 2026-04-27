# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::SubmitFormva401330mJob, type: :job do
  include Sidekiq::Testing

  before(:each) { Sidekiq::Testing.fake! }
  after(:each)  { Sidekiq::Worker.clear_all }

  let(:submission) { create(:formva40_1330m_submission) }

  # ---------------------------------------------------------------------------
  # Enqueueing
  # ---------------------------------------------------------------------------
  describe '.perform_async' do
    it 'enqueues exactly one job' do
      expect {
        described_class.perform_async(submission.id)
      }.to change(described_class.jobs, :size).by(1)
    end

    it 'enqueues the job with the correct submission_id argument' do
      described_class.perform_async(submission.id)
      enqueued_args = described_class.jobs.last['args']
      expect(enqueued_args).to eq([submission.id])
    end

    it 'targets the default queue' do
      described_class.perform_async(submission.id)
      expect(described_class.jobs.last['queue']).to eq('default')
    end
  end

  # ---------------------------------------------------------------------------
  # perform (synchronous execution via Sidekiq::Testing.inline! per test)
  # ---------------------------------------------------------------------------
  describe '#perform' do
    let(:pdf_path) { Rails.root.join('tmp', 'test_va40_1330m.pdf').to_s }
    let(:fake_confirmation) { 'lighthouse-uuid-test-1234' }

    before do
      # Stub PDF generator to return a predictable tmp path
      allow_any_instance_of(Formva401330mPdfGenerator)
        .to receive(:generate)
        .and_return(pdf_path)

      # Create a dummy tmp file so File.exist? passes in cleanup
      FileUtils.touch(pdf_path)

      # Stub Flipper flag — use PATH B in all job specs
      allow(Flipper).to receive(:enabled?).with(:headstone_marker_nca_direct_api).and_return(false)
    end

    after do
      FileUtils.rm_f(pdf_path)
    end

    context 'when Lighthouse benefits-intake returns HTTP 200' do
      before do
        stub_request(:post, /benefits-intake/)
          .to_return(
            status: 200,
            body:   { data: { id: fake_confirmation } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Stub the BenefitsIntakeService to return a success-like response
        allow_any_instance_of(BenefitsIntakeService::Service)
          .to receive(:upload_form)
          .and_return(
            instance_double(
              Faraday::Response,
              success?: true,
              status:   200,
              body:     { 'data' => { 'id' => fake_confirmation } }.to_json
            )
          )
      end

      it 'completes without raising an error' do
        expect { described_class.new.perform(submission.id) }.not_to raise_error
      end

      it 'updates the submission status to submitted' do
        described_class.new.perform(submission.id)
        expect(submission.reload.submission_status).to eq('submitted')
      end

      it 'sets the confirmation_number on the submission' do
        described_class.new.perform(submission.id)
        expect(submission.reload.confirmation_number).to eq(fake_confirmation)
      end

      it 'sets submitted_at on the submission' do
        described_class.new.perform(submission.id)
        expect(submission.reload.submitted_at).not_to be_nil
      end

      it 'increments the success StatsD counter' do
        expect(StatsD).to receive(:increment)
          .with('worker.va40_1330m_submission.success', tags: ['form:40-1330M'])
        allow(StatsD).to receive(:histogram)
        described_class.new.perform(submission.id)
      end

      it 'cleans up the tmp PDF file after successful submission' do
        described_class.new.perform(submission.id)
        expect(File.exist?(pdf_path)).to be(false)
      end
    end

    context 'when Lighthouse benefits-intake returns an error' do
      before do
        allow_any_instance_of(BenefitsIntakeService::Service)
          .to receive(:upload_form)
          .and_return(
            instance_double(
              Faraday::Response,
              success?: false,
              status:   503,
              body:     'Service Unavailable'
            )
          )
      end

      it 'raises a Lighthouse::BenefitsIntake::ServiceError' do
        expect {
          described_class.new.perform(submission.id)
        }.to raise_error(Lighthouse::BenefitsIntake::ServiceError)
      end

      it 'marks the submission as failed' do
        described_class.new.perform(submission.id) rescue nil
        expect(submission.reload.submission_status).to eq('failed')
      end

      it 'increments the intake_api_error StatsD counter' do
        expect(StatsD).to receive(:increment)
          .with('worker.va40_1330m_submission.intake_api_error', tags: ['form:40-1330M'])
        allow(StatsD).to receive(:increment)
        described_class.new.perform(submission.id) rescue nil
      end

      it 'captures the exception in Sentry' do
        expect(Sentry).to receive(:capture_exception)
        described_class.new.perform(submission.id) rescue nil
      end

      it 'still cleans up the tmp PDF even on failure' do
        described_class.new.perform(submission.id) rescue nil
        expect(File.exist?(pdf_path)).to be(false)
      end
    end

    context 'when the submission is already submitted (duplicate job guard)' do
      let(:submitted_submission) { create(:formva40_1330m_submission, :submitted) }

      it 'returns early without raising' do
        expect { described_class.new.perform(submitted_submission.id) }.not_to raise_error
      end

      it 'does not attempt PDF generation' do
        expect(Formva401330mPdfGenerator).not_to receive(:new)
        described_class.new.perform(submitted_submission.id)
      end

      it 'increments the duplicate_skip StatsD counter' do
        expect(StatsD).to receive(:increment).with('worker.va40_1330m_submission.duplicate_skip')
        described_class.new.perform(submitted_submission.id)
      end
    end

    context 'when PDF generation fails' do
      before do
        allow_any_instance_of(Formva401330mPdfGenerator)
          .to receive(:generate)
          .and_raise(Formva401330mPdfGenerator::GenerationError, 'PDF template not found')
      end

      it 'raises GenerationError' do
        expect {
          described_class.new.perform(submission.id)
        }.to raise_error(Formva401330mPdfGenerator::GenerationError)
      end

      it 'marks the submission as failed' do
        described_class.new.perform(submission.id) rescue nil
        expect(submission.reload.submission_status).to eq('failed')
      end

      it 'increments the pdf_generation_error StatsD counter' do
        expect(StatsD).to receive(:increment)
          .with('worker.va40_1330m_submission.pdf_generation_error', tags: ['form:40-1330M'])
        allow(StatsD).to receive(:increment)
        described_class.new.perform(submission.id) rescue nil
      end
    end

    context 'when PATH A flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:headstone_marker_nca_direct_api).and_return(true)
      end

      it 'raises NotImplementedError (PATH A not yet implemented)' do
        expect {
          described_class.new.perform(submission.id)
        }.to raise_error(NotImplementedError, /PATH A/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Sidekiq retry configuration
  # ---------------------------------------------------------------------------
  describe 'sidekiq options' do
    it 'retries up to 5 times' do
      expect(described_class.sidekiq_options['retry']).to eq(5)
    end

    it 'enables the dead job queue' do
      expect(described_class.sidekiq_options['dead']).to be(true)
    end
  end
end