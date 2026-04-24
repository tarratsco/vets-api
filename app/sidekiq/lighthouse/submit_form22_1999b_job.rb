# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module Lighthouse
  class SubmitForm22_1999bJob
    include Sidekiq::Worker

    sidekiq_options queue: :default, retry: 5

    STATS_KEY      = 'worker.lighthouse.submit_form22_1999b'
    FORM_ID        = '22-1999b'
    BENEFITS_INTAKE_DOC_TYPE = '22-1999b'

    # Sidekiq retry callback — logged to Sentry on final exhaustion
    sidekiq_retries_exhausted do |msg, ex|
      submission_id = msg['args'].first
      Sentry.capture_message(
        "SubmitForm22_1999bJob exhausted retries for submission #{submission_id}",
        extra: { exception: ex.message, jid: msg['jid'] }
      )
      StatsD.increment("#{STATS_KEY}.exhausted")

      # Mark the submission so operators can identify stranded records
      submission = Form22_1999bSubmission.find_by(id: submission_id)
      submission&.update_columns(submission_error: ex.message[0..500])
    rescue StandardError => e
      Rails.logger.error("SubmitForm22_1999bJob retries_exhausted callback failed: #{e.message}")
    end

    # -----------------------------------------------------------------------
    # Main perform method
    # Fetches the submission record, generates a PDF, uploads to Lighthouse
    # Benefits Intake API, and marks the record as submitted on success.
    # -----------------------------------------------------------------------
    def perform(submission_id)
      submission = Form22_1999bSubmission.find(submission_id)
      form       = submission.form_model

      StatsD.increment("#{STATS_KEY}.attempt")

      Rails.logger.info(
        "SubmitForm22_1999bJob: starting submission #{submission_id}, " \
        "facility=#{sanitized_facility_code(form)}"
      )

      Datadog::Tracing.trace('lighthouse.submit_form22_1999b') do |span|
        span.set_tag('form_id', FORM_ID)
        span.set_tag('submission_id', submission_id)

        intake_response = upload_to_benefits_intake(form, submission)
        guid            = intake_response[:guid] || intake_response['guid']

        submission.mark_submitted!(guid)

        StatsD.increment("#{STATS_KEY}.success",
                         tags: ["change_type:#{form.type_of_change}",
                                "chapter:#{form.benefit_chapter}"])

        Rails.logger.info(
          "SubmitForm22_1999bJob: submission #{submission_id} succeeded, " \
          "intake_guid=#{guid}"
        )
      end
    rescue ActiveRecord::RecordNotFound => e
      # If the record was deleted before the job ran, do not retry.
      Rails.logger.error("SubmitForm22_1999bJob: submission #{submission_id} not found — #{e.message}")
      StatsD.increment("#{STATS_KEY}.record_not_found")
      # Do not re-raise — job is considered complete (no record to process)
    rescue Lighthouse::BenefitsIntake::InvalidDocumentError => e
      StatsD.increment("#{STATS_KEY}.invalid_document")
      Sentry.capture_exception(e, extra: { submission_id: submission_id })
      raise # Allow Sidekiq retry
    rescue StandardError => e
      StatsD.increment("#{STATS_KEY}.error", tags: ["error_class:#{e.class}"])
      Sentry.capture_exception(e, extra: { submission_id: submission_id })
      raise # Allow Sidekiq retry
    end

    private

    def upload_to_benefits_intake(form, submission)
      # Generate the filled PDF from form data.
      # NOTE: PDF template must be in place at lib/pdf_fill/forms/pdftk/VA22-1999b.pdf
      # before the Option B submission path is production-ready (see Architecture Intent OQ-3).
      pdf_path = generate_pdf(form)

      # Build metadata for Lighthouse routing
      metadata = form.metadata

      # Initialize Lighthouse Benefits Intake service
      intake_service = BenefitsIntake::Service.new

      # Obtain an upload location and GUID from Lighthouse
      upload_data = intake_service.request_upload

      # Upload the filled PDF using the presigned location
      intake_service.upload_document(
        upload_url:  upload_data[:location] || upload_data['location'],
        file_path:   pdf_path,
        metadata:    metadata,
        attachments: supporting_document_paths(form)
      )

      { guid: upload_data[:guid] || upload_data['guid'] }
    ensure
      # Clean up temp PDF if it was written to disk
      File.delete(pdf_path) if pdf_path && File.exist?(pdf_path)
    end

    def generate_pdf(form)
      PdfFill::Filler.fill_form(
        form_id:   FORM_ID,
        form_data: form.data
      )
    rescue PdfFill::Filler::PdfFillerUnavailableError => e
      # PDF filling unavailable — log and raise to trigger retry
      Rails.logger.error("SubmitForm22_1999bJob: PDF generation failed — #{e.message}")
      raise
    end

    def supporting_document_paths(form)
      doc_ids = form.data.dig('supportingDocumentation', 'supportingDocumentIds') ||
                form.data.dig('supporting_documentation', 'supporting_document_ids') || []
      return [] if doc_ids.empty?

      doc_ids.filter_map do |doc_id|
        fetch_s3_document_path(doc_id)
      end
    end

    def fetch_s3_document_path(document_id)
      # Download supporting document from S3 to a temp path for bundling.
      # The S3 key convention matches the upload path set in the document uploader.
      key      = "edu-benefits/22-1999b/#{document_id}"
      tmp_path = Rails.root.join('tmp', "22_1999b_doc_#{document_id}")

      S3Utilities.download_object(bucket: Settings.edu_benefits.s3_bucket, key: key, destination: tmp_path.to_s)
      tmp_path.to_s
    rescue StandardError => e
      Rails.logger.warn("SubmitForm22_1999bJob: could not fetch supporting doc #{document_id}: #{e.message}")
      nil
    end

    def sanitized_facility_code(form)
      form.facility_code.to_s.gsub(/[^0-9]/, '')
    end
  end
end