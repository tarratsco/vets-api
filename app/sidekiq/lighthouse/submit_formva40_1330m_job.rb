# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module Lighthouse
  # Asynchronously submits a VA Form 40-1330M to the Lighthouse
  # benefits-intake API (Central Mail pipeline — PATH B per architecture intent
  # §3.4). Switches to PATH A (direct NCA API) when the
  # `headstone_marker_nca_direct_api` Flipper flag is enabled.
  #
  # Retry behaviour: 5 attempts with exponential back-off (Sidekiq default).
  # Dead-job queue is enabled; operations team monitors via Sidekiq Pro UI.
  class SubmitFormva401330mJob
    include Sidekiq::Job

    sidekiq_options queue:  'default',
                    retry:  5,
                    dead:   true,
                    tags:   ['va40_1330m', 'nca', 'benefits_intake']

    STATS_PREFIX  = 'worker.va40_1330m_submission'
    FORM_NUMBER   = '40-1330M'
    # ⚠️ UNVERIFIED — confirm NCA business line code with Central Mail team
    BUSINESS_LINE = 'NCA'

    def perform(submission_id)
      start_time = Time.current
      submission  = Formva401330mSubmission.find(submission_id)

      return if already_submitted?(submission)

      pdf_path = nil

      begin
        # Step 1 — generate filled PDF
        pdf_path = Formva401330mPdfGenerator.new(submission.form_data).generate

        # Step 2 — build submission metadata
        meta = build_metadata(submission)

        # Step 3 — submit via Lighthouse (PATH B) or direct NCA API (PATH A)
        result = if Flipper.enabled?(:headstone_marker_nca_direct_api)
                   submit_path_a(submission.form_data, pdf_path)
                 else
                   submit_path_b(meta, pdf_path, submission.form_data)
                 end

        # Step 4 — persist confirmation
        submission.update!(
          confirmation_number: result[:confirmation_number],
          submission_status:   'submitted',
          submitted_at:        Time.current
        )

        duration = Time.current - start_time
        StatsD.increment("#{STATS_PREFIX}.success", tags: ["form:#{FORM_NUMBER}"])
        StatsD.histogram("#{STATS_PREFIX}.duration", duration, tags: ["form:#{FORM_NUMBER}"])

        Rails.logger.info(
          msg:                'Formva401330m submission succeeded',
          submission_id:      submission_id,
          confirmation_number: result[:confirmation_number],
          duration_seconds:   duration.round(3)
        )

      rescue Lighthouse::BenefitsIntake::ServiceError => e
        handle_intake_error(submission, e)
        raise

      rescue Formva401330mPdfGenerator::GenerationError => e
        handle_pdf_error(submission, e)
        raise

      rescue => e
        handle_unexpected_error(submission, e)
        raise

      ensure
        # Always clean up tmp PDF regardless of success or failure
        cleanup_pdf(pdf_path)
      end
    end

    private

    # -------------------------------------------------------------------------
    # Guard against double-processing (e.g. Sidekiq retry after partial success)
    # -------------------------------------------------------------------------
    def already_submitted?(submission)
      if submission.submission_status == 'submitted'
        Rails.logger.info(
          msg:           'Formva401330m already submitted — skipping duplicate job',
          submission_id: submission.id
        )
        StatsD.increment("#{STATS_PREFIX}.duplicate_skip")
        return true
      end
      false
    end

    # -------------------------------------------------------------------------
    # PATH B — Lighthouse benefits-intake API (Central Mail pipeline)
    # -------------------------------------------------------------------------
    def submit_path_b(metadata, pdf_path, form_data)
      service = BenefitsIntakeService::Service.new

      document_uploads = collect_document_uploads(form_data)

      response = service.upload_form(
        main_document: pdf_upload_hash(pdf_path),
        attachments:   document_uploads,
        form_metadata: metadata
      )

      unless response.success?
        raise Lighthouse::BenefitsIntake::ServiceError,
              "Benefits-intake API returned #{response.status}: #{response.body}"
      end

      body = JSON.parse(response.body)
      { confirmation_number: body.dig('data', 'id') || body['uuid'] }
    end

    # -------------------------------------------------------------------------
    # PATH A — Direct NCA API via Lighthouse (placeholder; enable via flag)
    # ⚠️ UNVERIFIED — NCA Lighthouse endpoint does not exist yet.
    # -------------------------------------------------------------------------
    def submit_path_a(form_data, pdf_path)
      # TODO: replace with NcaDirectApiService once NCA IT architecture review
      # (Open Question AQ-1) is resolved and the Lighthouse NCA endpoint is live.
      raise NotImplementedError,
            'NCA direct API (PATH A) is not yet implemented. ' \
            'Disable the headstone_marker_nca_direct_api flag to use PATH B.'
    end

    # -------------------------------------------------------------------------
    # Build Central Mail / benefits-intake metadata hash
    # -------------------------------------------------------------------------
    def build_metadata(submission)
      data = submission.form_data
      {
        'veteranFirstName'   => data.dig('decedent', 'name', 'first').to_s,
        'veteranLastName'    => data.dig('decedent', 'name', 'last').to_s,
        'fileNumber'         => data.dig('decedent', 'ssn').to_s,
        'zipCode'            => data.dig('applicant', 'address', 'postalCode').to_s,
        'source'             => 'VA Platform Digital Forms',
        'docType'            => FORM_NUMBER,
        'businessLine'       => BUSINESS_LINE
      }
    end

    # -------------------------------------------------------------------------
    # Collect already-uploaded document S3 references for attachment bundle
    # -------------------------------------------------------------------------
    def collect_document_uploads(form_data)
      docs       = form_data['documents'] || {}
      uploads    = []

      %w[ddForm1300 ngbForm22 authorizationDocument].each do |doc_key|
        doc = docs[doc_key]
        next unless doc&.dig('confirmationCode').present?

        uploads << {
          confirmation_code: doc['confirmationCode'],
          name:              doc['name'],
          attachment_type:   doc_key
        }
      end

      (docs['additionalDocuments'] || []).each_with_index do |doc, idx|
        next unless doc&.dig('confirmationCode').present?

        uploads << {
          confirmation_code: doc['confirmationCode'],
          name:              doc['name'] || "additional_document_#{idx + 1}",
          attachment_type:   'additionalDocument'
        }
      end

      uploads
    end

    def pdf_upload_hash(pdf_path)
      {
        file_name:    File.basename(pdf_path),
        file_path:    pdf_path,
        content_type: 'application/pdf'
      }
    end

    # -------------------------------------------------------------------------
    # Error handlers — mark record failed and emit metrics before re-raising
    # -------------------------------------------------------------------------
    def handle_intake_error(submission, error)
      submission.update(submission_status: 'failed') rescue nil
      StatsD.increment("#{STATS_PREFIX}.intake_api_error", tags: ["form:#{FORM_NUMBER}"])
      Rails.logger.error(
        msg:           'Formva401330m Lighthouse intake error',
        error_class:   error.class.name,
        error_message: error.message,
        submission_id: submission.id
      )
      Sentry.capture_exception(error)
    end

    def handle_pdf_error(submission, error)
      submission.update(submission_status: 'failed') rescue nil
      StatsD.increment("#{STATS_PREFIX}.pdf_generation_error", tags: ["form:#{FORM_NUMBER}"])
      Rails.logger.error(
        msg:           'Formva401330m PDF generation error',
        error_class:   error.class.name,
        error_message: error.message,
        submission_id: submission.id
      )
      Sentry.capture_exception(error)
    end

    def handle_unexpected_error(submission, error)
      submission.update(submission_status: 'failed') rescue nil
      StatsD.increment("#{STATS_PREFIX}.unexpected_error", tags: ["form:#{FORM_NUMBER}"])
      Rails.logger.error(
        msg:           'Formva401330m unexpected job error',
        error_class:   error.class.name,
        error_message: error.message,
        submission_id: submission.id
      )
      Sentry.capture_exception(error)
    end

    def cleanup_pdf(pdf_path)
      return unless pdf_path.present? && File.exist?(pdf_path.to_s)

      File.delete(pdf_path)
    rescue Errno::ENOENT
      # Already cleaned up — safe to ignore
    end
  end
end