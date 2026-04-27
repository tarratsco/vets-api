# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module V0
  class Formva401330mController < ApplicationController
    include ActionController::MimeResponds

    service_tag 'veteran-facing-forms'

    before_action :authenticate
    before_action :verify_loa3!

    # --------------------------------------------------------------------------
    # POST /v0/formva40_1330m
    #
    # Validates submitted form data, persists a Formva401330mSubmission record,
    # enqueues an async Lighthouse benefits-intake job, and returns a 200 with
    # the serialized submission.  Returns 422 on validation failure.
    # --------------------------------------------------------------------------
    def create
      submission = Formva401330mSubmission.new(
        form_data: permitted_params.to_h,
        user_uuid: current_user.uuid
      )

      unless submission.valid?
        StatsD.increment("#{STATS_PREFIX}.submission.validation_failure")
        render json:   { errors: submission.errors.full_messages },
               status: :unprocessable_entity
        return
      end

      submission.save!

      Lighthouse::SubmitFormva401330mJob.perform_async(submission.id)

      StatsD.increment("#{STATS_PREFIX}.submission.enqueued")

      render json:   Formva401330mSerializer.new(submission),
             status: :ok

    rescue ActiveRecord::RecordInvalid => e
      StatsD.increment("#{STATS_PREFIX}.submission.record_invalid")
      Rails.logger.warn(
        msg:            'Formva401330m record invalid',
        error:          e.message,
        user_uuid:      current_user&.uuid,
        correlation_id: request.env['HTTP_X_REQUEST_ID']
      )
      render json:   { errors: [e.message] },
             status: :unprocessable_entity

    rescue => e
      StatsD.increment("#{STATS_PREFIX}.submission.unexpected_error")
      Rails.logger.error(
        msg:            'Formva401330m unexpected controller error',
        error_class:    e.class.name,
        user_uuid:      current_user&.uuid,
        correlation_id: request.env['HTTP_X_REQUEST_ID']
      )
      Sentry.capture_exception(e)
      raise
    end

    private

    STATS_PREFIX = 'api.burial_forms.va40_1330m'

    # --------------------------------------------------------------------------
    # LOA3 guard — applicants who are LOA1/LOA2 receive HTTP 403.
    # --------------------------------------------------------------------------
    def verify_loa3!
      return if current_user&.loa3?

      render json:   { errors: ['LOA3 authentication required'] },
             status: :forbidden
    end

    # --------------------------------------------------------------------------
    # Strong parameters — mirrors the JSON schema structure.
    # Note: additionalDocuments is expressed as an array of hashes.
    # --------------------------------------------------------------------------
    def permitted_params
      params.require(:formva40_1330m).permit(
        :serviceStatusAtDeath,
        :guardReserveQualifyingCircumstance,
        :submitterRole,
        :certificationAttestation,
        applicant: [
          :daytimePhone,
          :email,
          :relationshipToDecedent,
          :relationshipDescription,
          :organizationName,
          :organizationRole,
          :legalAuthorityDescription,
          name: %i[first middle last suffix],
          address: %i[street street2 city state postalCode country],
          authorizationDocument: %i[name size confirmationCode attachmentId]
        ],
        decedent: [
          :ssn,
          :dateOfBirth,
          :dateOfDeath,
          name: %i[first middle last suffix],
          placeOfDeath: %i[city state country],
          service: %i[
            branchOfService
            component
            rankAtDeath
            serviceNumber
            serviceEntryDate
            serviceEndDate
          ]
        ],
        burialLocation: [
          :cemeteryName,
          :cemeteryContactName,
          :cemeteryContactPhone,
          :graveSection,
          :graveLot,
          :graveNumber,
          :existingMarkerPresent,
          cemeteryAddress: %i[street street2 city state postalCode country]
        ],
        markerRequest: %i[markerType emblemOfBelief personalInscription],
        documents: [
          deathCertificate:       %i[name size confirmationCode attachmentId],
          ddForm1300:             %i[name size confirmationCode attachmentId],
          ngbForm22:              %i[name size confirmationCode attachmentId],
          authorizationDocument:  %i[name size confirmationCode attachmentId],
          additionalDocuments:    %i[name size confirmationCode attachmentId]
        ]
      )
    end
  end
end