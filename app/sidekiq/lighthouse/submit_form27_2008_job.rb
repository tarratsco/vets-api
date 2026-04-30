# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module Lighthouse
  class SubmitForm27_2008Job
    include Sidekiq::Worker

    sidekiq_options(
      retry:        5,
      queue:        'default',
      unique:       :until_executed,
      unique_args:  ->(args) { [args.first] } # dedup by submission_id
    )

    STATS_KEY   = 'api.form27_2008.benefits_intake'
    FORM_ID     = '27-2008'

    # Exponential back-off: 1m, 8m, 27m, 1h, 3.25h
    sidekiq_retry_in { |count| (count + 1) ** 3 * 60 }

    # -------------------------------------------------------------------------
    # perform
    # -------------------------------------------------------------------------

    def perform(submission_id)
      submission = Form27_2008Submission.find(submission_id)

      if submission.submitted?
        Rails.logger.info(
          message: 'form27_2008_submission_already_submitted',
          submission_id: submission_id
        )
        return
      end

      StatsD.increment("#{STATS_KEY}.attempt")

      start_time = Time.current
      result = submit_to_benefits_intake(submission)

      elapsed_ms = ((Time.current - start_time) * 1000).round
      StatsD.timing("#{STATS_KEY}.latency", elapsed_ms)

      confirmation_number = extract_confirmation_number(result, submission)
      submission.mark_submitted!(confirmation_number)

      StatsD.increment("#{STATS_KEY}.success")

      Rails.logger.info(
        message: 'form27_2008_submission_succeeded',
        submission_id: submission_id,
        confirmation_number: confirmation_number,
        duration_ms: elapsed_ms
      )
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error(
        message: 'form27_2008_submission_record_not_found',
        submission_id: submission_id,
        error: e.message
      )
      StatsD.increment("#{STATS_KEY}.failure", tags: ['error_type:record_not_found'])
      # Do not retry — the record is gone
      raise Sidekiq::JobRetry::Skip
    rescue BenefitsIntakeError => e
      StatsD.increment("#{STATS_KEY}.failure", tags: ["error_type:benefits_intake"])
      Rails.logger.error(
        message: 'form27_2008_benefits_intake_error',
        submission_id: submission_id,
        error: e.message
      )
      raise # allow Sidekiq retry
    rescue => e
      StatsD.increment("#{STATS_KEY}.failure", tags: ["error_type:#{e.class}"])
      Rails.logger.error(
        message: 'form27_2008_submission_error',
        submission_id: submission_id,
        error: e.message,
        error_class: e.class.to_s
      )
      raise # allow Sidekiq retry
    end

    # -------------------------------------------------------------------------
    # Custom error class
    # -------------------------------------------------------------------------

    class BenefitsIntakeError < StandardError; end

    private

    # -------------------------------------------------------------------------
    # Benefits Intake API submission
    # -------------------------------------------------------------------------

    def submit_to_benefits_intake(submission)
      service = build_benefits_intake_service

      # Assemble the PDF from form data
      pdf_path = generate_pdf(submission)

      # Collect any uploaded document attachments by GUID
      attachments = collect_attachments(submission)

      begin
        response = service.upload_doc(
          upload_url:  upload_location(service),
          file:        pdf_path,
          metadata:    build_metadata(submission),
          attachments: attachments
        )
        raise BenefitsIntakeError, "Benefits Intake API returned #{response.status}" unless response.success?

        response
      ensure
        cleanup_temp_pdf(pdf_path)
      end
    end

    def build_benefits_intake_service
      BenefitsIntakeService::Service.new
    end

    def upload_location(service)
      response = service.request_upload
      raise BenefitsIntakeError, 'Failed to obtain upload location' unless response.success?

      response.body.dig('data', 'attributes', 'uploadUrl')
    end

    def generate_pdf(submission)
      Form27_2008PdfGenerator.new(submission.form_data).generate
    end

    def collect_attachments(submission)
      uploads = submission.form_data.dig('documents', 'dd214Upload') || []
      uploads.filter_map do |upload|
        guid = upload['guid']
        next if guid.blank?

        retrieve_staged_document(guid)
      end
    end

    def retrieve_staged_document(guid)
      # Retrieve staged file from CarrierWave / S3 temp storage by GUID.
      # Returns a file path string or nil if the document has expired.
      uploader = BurialFlagDocumentUploader.new
      uploader.retrieve_from_store!(guid)
      uploader.path
    rescue CarrierWave::InvalidParameter, Errno::ENOENT => e
      Rails.logger.warn(
        message: 'form27_2008_staged_document_not_found',
        guid: guid,
        error: e.message
      )
      nil
    end

    def build_metadata(submission)
      form = SimpleFormsApi::VBA272008.new(submission.form_data)
      form.metadata.merge(
        'receiveDt'          => submission.created_at.strftime('%Y-%m-%d %H:%M:%S'),
        'uuid'               => submission.id.to_s,
        'confirmationNumber' => submission.confirmation_number
      )
    end

    def extract_confirmation_number(response, submission)
      # Prefer the UUID returned by Benefits Intake API; fall back to the
      # pre-generated confirmation number on the submission record.
      api_uuid = response.body&.dig('data', 'attributes', 'guid')
      return submission.confirmation_number if api_uuid.blank?

      # Format the Benefits Intake UUID as a human-readable confirmation string
      date_part = submission.created_at.strftime('%Y%m%d')
      "BF-#{date_part}-#{api_uuid.upcase.first(8)}"
    end

    def cleanup_temp_pdf(pdf_path)
      FileUtils.rm_f(pdf_path) if pdf_path.present? && File.exist?(pdf_path)
    rescue => e
      Rails.logger.warn(
        message: 'form27_2008_temp_pdf_cleanup_error',
        pdf_path: pdf_path,
        error: e.message
      )
    end
  end
end