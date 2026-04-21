# app/sidekiq/lighthouse/submit_22_1999_job.rb
# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module Lighthouse
  class Submit221999Job
    include Sidekiq::Job
    include SentryLogging

    FORM_ID          = '22-1999'
    STATSD_PREFIX    = 'worker.lighthouse.submit_22_1999'
    POLL_TIMEOUT_HRS = 72

    sidekiq_options(
      queue:       :default,
      retry:       7,
      dead:        true,
      unique:      :until_executed,
      unique_args: ->(args) { args }
    )

    sidekiq_retries_exhausted do |msg, _ex|
      submission_id = msg['args'].first
      Rails.logger.error(
        "#{STATSD_PREFIX}: retries_exhausted for submission_id=#{submission_id} — " \
        "error=#{msg['error_message']}"
      )
      StatsD.increment("#{STATSD_PREFIX}.retries_exhausted")

      begin
        submission = EnrollmentCertification.find(submission_id)
        submission.update!(
          status:        :failed,
          error_message: "Retries exhausted: #{msg['error_message']}"
        )
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error("#{STATSD_PREFIX}: retries_exhausted — submission #{submission_id} not found")
      end
    end

    # -------------------------------------------------------------------------
    # perform
    # -------------------------------------------------------------------------

    def perform(submission_id)
      submission = EnrollmentCertification.find(submission_id)

      # Guard: skip if already successfully submitted (idempotency)
      if submission.success?
        Rails.logger.info("#{STATSD_PREFIX}: skipping submission_id=#{submission_id} — already succeeded")
        return
      end

      Rails.logger.info("#{STATSD_PREFIX}: starting submission_id=#{submission_id}")
      StatsD.increment("#{STATSD_PREFIX}.attempt")

      submission.update!(status: :processing)

      begin
        # Build the metadata and upload payload
        metadata = build_metadata(submission)
        payload  = build_payload(submission)

        # Upload to Lighthouse Benefits Intake API
        service  = BenefitsIntake::Service.new
        response = service.upload_doc(
          upload_url:  prepare_upload_url(service),
          file:        generate_pdf(submission),
          metadata:    metadata,
          attachments: []
        )

        handle_success(submission, response)

      rescue BenefitsIntake::ServiceException => e
        handle_benefits_intake_error(submission, e)
        raise # re-raise to trigger Sidekiq retry
      rescue => e
        handle_unexpected_error(submission, e)
        raise # re-raise to trigger Sidekiq retry
      end
    end

    private

    # -------------------------------------------------------------------------
    # Submission helpers
    # -------------------------------------------------------------------------

    def prepare_upload_url(service)
      response = service.request_upload
      raise BenefitsIntake::ServiceException, 'Failed to obtain upload URL' unless response[:location]
      response[:location]
    end

    def build_metadata(submission)
      student_info    = submission.student_information || {}
      sco_info        = submission.certifying_official || {}
      institution_info = submission.institution_information || {}

      {
        veteranFirstName:  student_info['firstName'] || '',
        veteranLastName:   student_info['lastName']  || '',
        fileNumber:        student_info['vaFileNumber'] || student_info['ssn'] || '',
        zipCode:           extract_zip_code(institution_info),
        source:            'VA.gov',
        docType:           FORM_ID,
        businessLine:      'EDU',
        originalUploadDate: Time.zone.now.iso8601,
        submittingUserUuid: submission.user_uuid
      }
    end

    def build_payload(submission)
      # Augment form_data with server-side submission metadata
      submission.form_data.merge(
        'submissionMetadata' => {
          'submittedAt'   => Time.zone.now.iso8601,
          'formVersion'   => 0,
          'vaProfileId'   => submission.user_uuid
          # ipAddress intentionally omitted from persisted payload per schema note §6
        }
      )
    end

    def generate_pdf(submission)
      # Delegates to the form's PDF transformer.
      # Returns a Tempfile or path string.
      transformer = EnrollmentCertificationPdfTransformer.new(submission)
      transformer.generate
    rescue NameError
      # Fallback during development before PDF transformer is implemented:
      # produce a minimal JSON file so the upload can proceed in staging.
      Rails.logger.warn("#{STATSD_PREFIX}: PDF transformer not available — using JSON fallback")
      json_fallback(submission)
    end

    def json_fallback(submission)
      tmp = Tempfile.new(["22_1999_#{submission.id}", '.json'])
      tmp.write(submission.form_data.to_json)
      tmp.flush
      tmp
    end

    def extract_zip_code(institution_info)
      institution_info.dig('institutionAddress', 'postalCode')&.gsub(/[^0-9]/, '')&.first(5) || '00000'
    end

    def handle_success(submission, response)
      guid = response[:uuid] || response&.dig('data', 'id')
      submission.update!(
        status:              :success,
        confirmation_number: guid,
        submitted_at:        Time.zone.now,
        transaction_id:      guid,
        error_message:       nil
      )
      StatsD.increment("#{STATSD_PREFIX}.success")
      Rails.logger.info(
        "#{STATSD_PREFIX}: success submission_id=#{submission.id} confirmation=#{guid}"
      )
    end

    def handle_benefits_intake_error(submission, error)
      error_msg = error.message.truncate(1000)
      Rails.logger.error(
        "#{STATSD_PREFIX}: BenefitsIntake error submission_id=#{submission.id} — #{error_msg}"
      )
      StatsD.increment("#{STATSD_PREFIX}.benefits_intake_error")
      log_exception_to_sentry(error, { submission_id: submission.id, form_id: FORM_ID })
      submission.update!(status: :failed, error_message: error_msg)
    end

    def handle_unexpected_error(submission, error)
      error_msg = error.message.truncate(1000)
      Rails.logger.error(
        "#{STATSD_PREFIX}: unexpected error submission_id=#{submission.id} — #{error_msg}"
      )
      StatsD.increment("#{STATSD_PREFIX}.unexpected_error")
      log_exception_to_sentry(error, { submission_id: submission.id, form_id: FORM_ID })
      submission.update!(status: :failed, error_message: error_msg)
    end
  end
end