# frozen_string_literal: true

require 'simple_forms_api/form_remediation/configuration/vff_config'

module V0
  class Form22_1999bController < ApplicationController
    include ActionController::MimeResponds

    before_action :authenticate
    before_action :require_loa2_or_higher

    FORM_ID = '22-1999b'

    PERMITTED_PARAMS = {
      institutionAndScoInformation: [
        :facilityCode,
        :institutionName,
        :scoFirstName,
        :scoLastName,
        :scoTitle,
        :scoPhone,
        :scoEmail,
        { institutionAddress: %i[street city state zip] }
      ],
      studentAndPriorCertification: [
        :studentFirstName,
        :studentLastName,
        :ssnOrFileNumberIndicator,
        :studentSsn,
        :studentVaFileNumber,
        :benefitChapter,
        :originalCertBeginDate,
        :originalCertEndDate,
        :originalCreditHours,
        :originalEnrollmentType,
        :vaonceCertId
      ],
      enrollmentChangeDetails: [
        :typeOfChange,
        :effectiveDateOfChange,
        :lastDateOfAttendance,
        :reasonForChange,
        :lateSubmissionExplanation,
        {
          updatedEnrollmentDetails: %i[newCreditHours newEnrollmentType],
          mitigatingCircumstances: %i[
            mitigatingCircumstancesKnown
            mitigatingCircumstancesNarrative
          ],
          correctionDetails: [
            :correctedCreditHours,
            :correctedCertBeginDate,
            :correctedCertEndDate,
            :correctedEnrollmentType,
            :correctedTuitionFeesAmount,
            :correctedStudentFirstName,
            :correctedStudentLastName,
            :correctedStudentSsn,
            :correctedBenefitChapter,
            :correctionOtherDescription,
            { correctionItems: [] }
          ]
        }
      ],
      supportingDocumentation: [{ supportingDocumentIds: [] }],
      scoCertificationAttested: nil
    }.freeze

    def create
      StatsD.increment("#{STATS_KEY}.submission.attempt")

      form_data_params = permitted_form_params
      form = build_form_model(form_data_params)

      unless form_valid?(form, form_data_params)
        StatsD.increment("#{STATS_KEY}.submission.validation_failure")
        return render json: { errors: @validation_errors }, status: :unprocessable_entity
      end

      submission = Form22_1999bSubmission.new(
        user_uuid:  current_user.uuid,
        form_data:  form_data_params.to_unsafe_h.to_json
      )

      unless submission.save
        StatsD.increment("#{STATS_KEY}.submission.save_failure")
        return render json: { errors: submission.errors.full_messages },
                      status: :unprocessable_entity
      end

      Lighthouse::SubmitForm22_1999bJob.perform_async(submission.id)
      StatsD.increment("#{STATS_KEY}.submission.job_enqueued")

      render json: Form22_1999bSerializer.new(submission).serializable_hash,
             status: :created

    rescue ActionController::ParameterMissing => e
      render json: { errors: [e.message] }, status: :unprocessable_entity
    rescue StandardError => e
      StatsD.increment("#{STATS_KEY}.submission.error")
      Sentry.capture_exception(e, extra: { user_uuid: current_user&.uuid })
      render json: { errors: ['An unexpected error occurred. Please try again.'] },
             status: :internal_server_error
    end

    private

    STATS_KEY = 'api.form22_1999b'

    def require_loa2_or_higher
      unless current_user&.loa3? || current_user&.loa2?
        render json: { errors: ['Identity verification required to submit this form.'] },
               status: :forbidden
      end
    end

    def permitted_form_params
      params.require(:form22_1999b).permit(PERMITTED_PARAMS)
    end

    def build_form_model(permitted_params)
      SimpleFormsApi::VBA221999b.new(permitted_params.to_unsafe_h)
    end

    # Run cross-field ActiveModel-style validations that JSON Schema cannot express
    def form_valid?(form, params)
      @validation_errors = []

      validate_attestation(params)
      validate_student_identifier(form)
      validate_dates(form)
      validate_conditional_fields(form)
      validate_correction_fields(form)
      validate_late_submission(form)

      @validation_errors.empty?
    end

    def validate_attestation(params)
      attested = params[:scoCertificationAttested]
      unless attested == true || attested == 'true'
        @validation_errors << 'SCO certification attestation must be accepted before submitting.'
      end
    end

    def validate_student_identifier(form)
      case form.ssn_or_file_number_indicator
      when 'ssn'
        if form.student_ssn.blank? || form.student_ssn !~ /\A\d{9}\z/
          @validation_errors << 'Student SSN must be 9 digits when SSN is the selected identifier.'
        end
      when 'va_file_number'
        if form.student_va_file_number.blank? || form.student_va_file_number !~ /\A\d{8,9}\z/
          @validation_errors << 'VA File Number must be 8 or 9 digits when VA File Number is the selected identifier.'
        end
      else
        @validation_errors << 'A student identifier type (SSN or VA File Number) must be selected.'
      end
    end

    def validate_dates(form)
      begin_date  = parse_date(form.original_cert_begin_date)
      end_date    = parse_date(form.original_cert_end_date)
      effective   = parse_date(form.effective_date_of_change)
      last_attend = parse_date(form.last_date_of_attendance)

      if begin_date && end_date && begin_date > end_date
        @validation_errors << 'Original certification begin date must be on or before end date.'
      end

      if effective && Date.current < effective
        @validation_errors << 'Effective date of change cannot be in the future.'
      end

      if effective && begin_date && effective < begin_date
        @validation_errors << 'Effective date of change must be on or after the original certification begin date.'
      end

      if effective && end_date && effective > end_date
        @validation_errors << 'Effective date of change must be on or before the original certification end date.'
      end

      if last_attend && effective && last_attend > effective
        @validation_errors << 'Last date of attendance must be on or before the effective date of change.'
      end
    end

    def validate_conditional_fields(form)
      case form.type_of_change
      when 'full_termination', 'partial_withdrawal'
        if form.last_date_of_attendance.blank?
          @validation_errors << 'Last date of attendance is required for termination or partial withdrawal.'
        end
        if form.type_of_change == 'partial_withdrawal' && form.updated_enrollment_details.blank?
          @validation_errors << 'Updated enrollment details are required for partial withdrawal.'
        end
      when 'credit_hour_reduction'
        if form.updated_enrollment_details.blank?
          @validation_errors << 'Updated enrollment details are required for credit hour reduction.'
        else
          new_hours = form.updated_enrollment_details['newCreditHours']
          orig_hours = form.original_credit_hours
          if new_hours && orig_hours && new_hours.to_i >= orig_hours.to_i
            @validation_errors << 'New credit hours must be less than original credit hours.'
          end
        end
      end

      if form.type_of_change != 'correction' && form.reason_for_change.blank?
        @validation_errors << 'Reason for change is required.'
      end

      if mitigating_circumstances_required?(form) && form.mitigating_circumstances_known.blank?
        @validation_errors << 'Mitigating circumstances response is required for this reason for change.'
      end

      if form.mitigating_circumstances_known == 'yes' && form.mitigating_circumstances_narrative.blank?
        @validation_errors << 'Mitigating circumstances narrative is required when mitigating circumstances are known.'
      end
    end

    def validate_correction_fields(form)
      return unless form.type_of_change == 'correction'

      if form.correction_items.blank?
        @validation_errors << 'At least one correction item must be selected for a correction submission.'
        return
      end

      items = form.correction_items
      cd    = form.correction_details

      if items.include?('credit_hours') && cd['correctedCreditHours'].blank?
        @validation_errors << 'Corrected credit hours are required when correcting credit hours.'
      end

      if items.include?('enrollment_dates')
        if cd['correctedCertBeginDate'].blank? || cd['correctedCertEndDate'].blank?
          @validation_errors << 'Corrected certification dates are required when correcting enrollment dates.'
        else
          cb = parse_date(cd['correctedCertBeginDate'])
          ce = parse_date(cd['correctedCertEndDate'])
          @validation_errors << 'Corrected begin date must be before corrected end date.' if cb && ce && cb > ce
        end
      end

      if items.include?('enrollment_type') && cd['correctedEnrollmentType'].blank?
        @validation_errors << 'Corrected enrollment type is required when correcting enrollment type.'
      end

      if items.include?('other') && cd['correctionOtherDescription'].blank?
        @validation_errors << 'A description is required when selecting "Other" as a correction item.'
      end
    end

    def validate_late_submission(form)
      return if form.type_of_change == 'correction'
      return unless form.late_submission?

      if form.late_submission_explanation.blank?
        @validation_errors << 'An explanation is required for submissions more than 30 days after the effective date of change.'
      end
    end

    def mitigating_circumstances_required?(form)
      mitigating_codes = SimpleFormsApi::VBA221999b::MITIGATING_REASON_CODES
      mitigating_codes.include?(form.reason_for_change)
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      Date.parse(date_string)
    rescue ArgumentError, TypeError
      nil
    end
  end
end