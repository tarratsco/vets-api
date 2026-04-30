# frozen_string_literal: true

require 'lighthouse/benefits_intake/service'

module V0
  class Form27_2008Controller < ApplicationController
    FORM_ID = '27-2008'
    STATS_KEY = 'api.form27_2008'

    # Require LOA3 (identity-verified) for all actions.
    # The architecture intent also supports an unauthenticated pathway,
    # but that pathway is handled through the simple_forms_api module's
    # UploadsController. This standalone controller enforces LOA3 and
    # is used for authenticated, session-backed submissions.
    before_action :authenticate
    before_action :require_loa3

    def create
      StatsD.increment("#{STATS_KEY}.submission.attempt",
                       tags: ["authenticated:#{current_user.present?}"])

      form = build_form
      unless form.valid_for_submission?
        log_validation_failure(form)
        render json: { errors: form.validation_errors },
               status: :unprocessable_entity
        return
      end

      submission = Form27_2008Submission.new(
        form_data: submission_params.to_unsafe_h,
        user_uuid: current_user&.uuid
      )

      unless submission.save
        render json: { errors: submission.errors.full_messages },
               status: :unprocessable_entity
        return
      end

      Lighthouse::SubmitForm27_2008Job.perform_async(submission.id)

      StatsD.increment("#{STATS_KEY}.submission.success",
                       tags: ["authenticated:#{current_user.present?}"])

      render json: Form27_2008Serializer.new(submission).serializable_hash,
             status: :ok
    rescue => e
      StatsD.increment("#{STATS_KEY}.submission.failure",
                       tags: ["authenticated:#{current_user.present?}", "error_type:#{e.class}"])
      log_exception_to_sentry(e, { form_id: FORM_ID, user_uuid: current_user&.uuid })
      raise
    end

    private

    def require_loa3
      unless current_user&.loa3?
        render json: { errors: ['User must be identity-verified (LOA3) to submit this form'] },
               status: :forbidden
        nil
      end
    end

    def build_form
      SimpleFormsApi::VBA272008.new(submission_params.to_unsafe_h)
    end

    def submission_params
      params.require(:burialFlagApplication).permit(
        :applicantType,
        :dateSigned,
        :certificationChecked,
        :remarks,
        veteranInformation: %i[
          firstName middleName lastName maidenOrOtherName
          vaFileNumber socialSecurityNumber militaryServiceNumber
          dateOfBirth dateOfDeath dateOfBurial
          placeOfBurialCemeteryName placeOfBurialCity placeOfBurialState
        ],
        serviceInformation: [
          branchOfService: [],
          :dateEnteredActiveDuty,
          :dateReleasedFromActiveDuty
        ],
        eligibility: [
          :documentationAvailable,
          :dischargeCharacter,
          reserveGuardCriteria: []
        ],
        flagRecipient: %i[
          recipientFullName recipientRelationship recipientRelationshipOther
          recipientAddressLine1 recipientAddressLine2
          recipientCity recipientState recipientZip recipientPhone
        ],
        applicant: %i[
          firstName middleName lastName
          addressLine1 addressLine2 city state zip
          relationshipToVeteran relationshipToVeteranOther
        ],
        documents: [
          dd214Upload: %i[name guid confirmationCode uploadedAt]
        ],
        metadata: %i[
          ineligibilityFlagged reserveGuardIneligibilityWarning submissionTimestamp
        ]
      )
    end

    def log_validation_failure(form)
      Rails.logger.warn(
        message: 'form27_2008_validation_failure',
        form_id: FORM_ID,
        errors: form.validation_errors,
        user_uuid: current_user&.uuid
      )
      StatsD.increment("#{STATS_KEY}.submission.failure",
                       tags: ["authenticated:#{current_user.present?}", 'error_type:validation'])
    end
  end
end