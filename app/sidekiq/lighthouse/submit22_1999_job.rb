# app/sidekiq/lighthouse/submit22_1999_job.rb
# frozen_string_literal: true

require 'sidekiq'

module Lighthouse
  class Submit22_1999Job
    include Sidekiq::Job

    # ---------------------------------------------------------------------------
    # Sidekiq configuration
    # ---------------------------------------------------------------------------

    sidekiq_options(
      queue:   'default',
      retry:   5,
      timeout: 25
    )

    FORM_ID             = '22-1999'.freeze
    STATSD_KEY_PREFIX   = 'worker.lighthouse.submit_22_1999'.freeze
    BENEFITS_INTAKE_URL = Settings.lighthouse.benefits_intake.url

    # Retry callback: record failure metrics and log warnings
    sidekiq_retries_exhausted do |msg, ex|
      submission_id = msg['args']&.first
      StatsD.increment("#{STATSD_KEY_PREFIX}.exhausted")
      Rails.logger.error(
        "[Submit22_1999Job] Retries exhausted for submission #{submission_id}: " \
        "#{ex.class} - #{ex.message}"
      )

      # Mark submission as permanently failed
      submission = EnrollmentCertification22_1999Submission.find_by(id: submission_id)
      submission&.update(status: 'failed')
    end

    # ---------------------------------------------------------------------------
    # Perform
    # ---------------------------------------------------------------------------

    def perform(submission_id)
      submission = EnrollmentCertification22_1999Submission.find(submission_id)

      unless submission.status == 'pending'
        Rails.logger.info("[Submit22_1999Job] Submission #{submission_id} is not pending (status=#{submission.status}); skipping")
        return
      end

      Rails.logger.info("[Submit22_1999Job] Starting submission for record #{submission_id}")

      timer = StatsD.time("#{STATSD_KEY_PREFIX}.duration") do
        upload_to_benefits_intake(submission)
      end

      StatsD.increment("#{STATSD_KEY_PREFIX}.success")
      Rails.logger.info("[Submit22_1999Job] Successfully submitted record #{submission_id}")
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.network_error")
      Rails.logger.warn("[Submit22_1999Job] Network error for submission #{submission_id}: #{e.message}")
      raise e  # Re-raise to trigger Sidekiq retry
    rescue Lighthouse::BenefitsIntake::Error => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.benefits_intake_error")
      Rails.logger.error("[Submit22_1999Job] Benefits Intake API error for submission #{submission_id}: #{e.message}")
      raise e  # Re-raise to trigger Sidekiq retry
    rescue ActiveRecord::RecordNotFound => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.not_found_error")
      Rails.logger.error("[Submit22_1999Job] Submission #{submission_id} not found: #{e.message}")
      # Do not retry for missing records
    rescue => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.unexpected_error")
      Rails.logger.error("[Submit22_1999Job] Unexpected error for submission #{submission_id}: #{e.class} - #{e.message}")
      raise e  # Re-raise to trigger Sidekiq retry
    end

    private

    # ---------------------------------------------------------------------------
    # Private helpers
    # ---------------------------------------------------------------------------

    def upload_to_benefits_intake(submission)
      client = build_benefits_intake_client

      # 1. Generate a PDF of the form data
      pdf_path = generate_pdf(submission)

      # 2. Obtain an upload location from Benefits Intake API
      upload_location = client.initiate_upload(
        metadata:       build_metadata(submission),
        document:       pdf_path,
        attachments:    []
      )

      # 3. Upload the PDF
      client.upload(
        upload_url:  upload_location.url,
        document:    pdf_path
      )

      # 4. Update submission record with confirmation info
      submission.update!(
        status:              'submitted',
        confirmation_number: upload_location.guid,
        submitted_at:        Time.zone.now
      )

      # 5. Cleanup temp PDF file
      File.delete(pdf_path) if File.exist?(pdf_path)
    end

    def build_benefits_intake_client
      Lighthouse::BenefitsIntake::Client.new(
        base_url:   BENEFITS_INTAKE_URL,
        api_key:    Settings.lighthouse.benefits_intake.api_key
      )
    end

    def build_metadata(submission)
      parsed = submission.parsed_form
      student = parsed['studentIdentification'] || {}
      inst    = parsed['institutionInformation'] || {}
      sco     = parsed['scoCertification']       || {}

      {
        veteranFirstName: student['studentFirstName'],
        veteranLastName:  student['studentLastName'],
        fileNumber:       student['studentVaFileNumber'] || student['studentSsn'],
        zipCode:          inst['zipCode'],
        source:           "va.gov enrollment certification #{FORM_ID}",
        docType:          FORM_ID,
        businessLine:     'EDU',
        submitterName:    "#{sco['scoFirstName']} #{sco['scoLastName']}".strip
      }
    end

    def generate_pdf(submission)
      pdf_generator = Lighthouse::Submit22_1999Job::PdfGenerator.new(submission)
      pdf_generator.generate
    end

    # ---------------------------------------------------------------------------
    # PDF Generator — inner class
    # ---------------------------------------------------------------------------

    class PdfGenerator
      def initialize(submission)
        @submission = submission
      end

      def generate
        tmp_file = Tempfile.new(["22_1999_#{@submission.id}_", '.pdf'])

        begin
          pdf = Prawn::Document.new

          pdf.text "VA Form 22-1999 Enrollment Certification", size: 18, style: :bold
          pdf.move_down 10
          pdf.text "Confirmation: #{@submission.confirmation_number || 'Pending'}", size: 12
          pdf.move_down 5
          pdf.text "Submitted: #{Time.zone.now.strftime('%Y-%m-%d')}", size: 10
          pdf.move_down 20

          render_form_sections(pdf)

          pdf.render_file(tmp_file.path)
          tmp_file.path
        ensure
          tmp_file.close
        end
      end

      private

      def render_form_sections(pdf)
        parsed = @submission.parsed_form

        render_section(pdf, 'Institution Information', parsed['institutionInformation'])
        render_section(pdf, 'Student Identification',  parsed['studentIdentification'])
        render_section(pdf, 'Benefit Chapter',         parsed['benefitChapter'])
        render_section(pdf, 'Enrollment Period',       parsed['enrollmentPeriod'])
        render_section(pdf, 'Program Information',     parsed['programInformation'])
        render_section(pdf, 'Credit Hours / Training Time', parsed['creditHoursTrainingTime'])
        render_section(pdf, 'Tuition & Fees',          parsed['tuitionFees']) if parsed['tuitionFees']
        render_section(pdf, 'Yellow Ribbon',           parsed['yellowRibbon']) if parsed['yellowRibbon']
        render_section(pdf, 'SCO Certification',       parsed['scoCertification'])
      end

      def render_section(pdf, title, data)
        return unless data.is_a?(Hash)

        pdf.text title, size: 14, style: :bold
        pdf.move_down 5

        data.each do |key, value|
          next if value.is_a?(Hash)

          label = key.gsub(/([A-Z])/, ' \1').capitalize
          pdf.text "#{label}: #{value}", size: 10
        end

        pdf.move_down 10
      end
    end
  end
end