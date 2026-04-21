# app/controllers/v0/education/enrollment_certifications_controller.rb
# frozen_string_literal: true

module V0
  module Education
    class EnrollmentCertificationsController < ApplicationController
      include SentryLogging

      FORM_ID = '22-1999'

      before_action :require_user
      before_action :require_loa3, only: %i[create show]

      # GET /v0/education/enrollment_certifications/:id
      def show
        submission = EnrollmentCertification.find_by!(
          id: params[:id],
          user_uuid: current_user.uuid
        )
        render json: EnrollmentCertificationSerializer.new(submission), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [{ title: 'Record not found', detail: 'Enrollment certification not found' }] },
               status: :not_found
      end

      # POST /v0/education/enrollment_certifications
      def create
        submission = EnrollmentCertification.new(
          user_uuid:         current_user.uuid,
          saved_claim_id:    nil,
          form_data:         filtered_form_data,
          status:            :pending
        )

        unless submission.valid?
          StatsD.increment("#{STATSD_PREFIX}.validation_failure")
          render json: {
            errors: submission.errors.full_messages.map { |msg| { title: 'Validation Error', detail: msg } }
          }, status: :unprocessable_entity
          return
        end

        submission.save!

        Lighthouse::Submit221999Job.perform_async(submission.id)
        StatsD.increment("#{STATSD_PREFIX}.submission_enqueued")

        render json: EnrollmentCertificationSerializer.new(submission), status: :created
      rescue ActiveRecord::RecordInvalid => e
        log_exception_to_sentry(e)
        StatsD.increment("#{STATSD_PREFIX}.record_invalid_error")
        render json: { errors: [{ title: 'Record Invalid', detail: e.message }] },
               status: :unprocessable_entity
      rescue => e
        log_exception_to_sentry(e)
        StatsD.increment("#{STATSD_PREFIX}.unexpected_error")
        render json: { errors: [{ title: 'Internal Server Error', detail: 'An unexpected error occurred' }] },
               status: :internal_server_error
      end

      private

      STATSD_PREFIX = 'api.v0.education.enrollment_certifications'

      # Permit and structure top-level form sections from the incoming params.
      # The JSON Schema sections map directly to these nested permit groups.
      def filtered_form_data
        raw = params.require(:form_data)

        raw_hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h

        # Strip server-only fields the client should never set
        raw_hash.deep_symbolize_keys.tap do |data|
          data.delete(:submissionMetadata)
          # ipAddress is server-injected at submission time
        end
      end

      def require_loa3
        return if current_user&.loa3?

        StatsD.increment("#{STATSD_PREFIX}.auth_failure_loa3")
        render json: {
          errors: [{ title: 'Forbidden', detail: 'LOA3 identity verification required to submit this form' }]
        }, status: :forbidden
      end

      def require_user
        return if current_user

        render json: {
          errors: [{ title: 'Unauthorized', detail: 'Authentication required' }]
        }, status: :unauthorized
      end
    end
  end
end