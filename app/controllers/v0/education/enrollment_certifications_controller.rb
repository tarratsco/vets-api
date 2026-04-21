# app/controllers/v0/education/enrollment_certifications_controller.rb
# frozen_string_literal: true

module V0
  module Education
    class EnrollmentCertificationsController < ApplicationController
      include SchemaValidation

      FORM_ID = '22-1999'

      before_action :require_user
      before_action :validate_schema, only: [:create]

      # POST /v0/education/enrollment_certifications
      def create
        form = EnrollmentCertification22_1999Form.new(
          submission_params.merge(user_uuid: current_user.uuid)
        )

        unless form.valid?
          StatsD.increment("#{STATSD_KEY_PREFIX}.validation_error")
          return render(
            json: { errors: form.errors.full_messages },
            status: :unprocessable_entity
          )
        end

        submission = EnrollmentCertification22_1999Submission.create!(
          user_uuid:       current_user.uuid,
          form_id:         FORM_ID,
          form_data:       submission_params.to_json,
          status:          'pending'
        )

        Lighthouse::Submit22_1999Job.perform_async(submission.id)

        StatsD.increment("#{STATSD_KEY_PREFIX}.submission_created")

        render(
          json:   V0::Education::EnrollmentCertification22_1999Serializer.new(submission),
          status: :created
        )
      rescue ActiveRecord::RecordInvalid => e
        StatsD.increment("#{STATSD_KEY_PREFIX}.record_invalid_error")
        render json: { errors: [e.message] }, status: :unprocessable_entity
      rescue => e
        StatsD.increment("#{STATSD_KEY_PREFIX}.unexpected_error")
        Rails.logger.error("[EnrollmentCertificationsController] Unexpected error: #{e.class} - #{e.message}")
        raise e
      end

      # GET /v0/education/enrollment_certifications/:id
      def show
        submission = EnrollmentCertification22_1999Submission.find_by!(
          id:        params[:id],
          user_uuid: current_user.uuid
        )

        render json: V0::Education::EnrollmentCertification22_1999Serializer.new(submission)
      rescue ActiveRecord::RecordNotFound
        render json: { errors: ['Submission not found'] }, status: :not_found
      end

      private

      STATSD_KEY_PREFIX = 'api.v0.education.enrollment_certifications'.freeze

      def require_user
        unless current_user
          render json: { errors: ['User is not authenticated'] }, status: :unauthorized
          return
        end

        unless current_user.loa3?
          render json: { errors: ['User must be identity-verified (LOA3) to submit this form'] }, status: :forbidden
        end
      end

      def validate_schema
        schema_path = Rails.root.join(
          'app', 'modules', 'v0', 'education', 'enrollment_certifications',
          'schemas', '22_1999_v1.json'
        )
        schema      = JSON.parse(File.read(schema_path))
        errors      = JSON::Validator.fully_validate(schema, submission_params.to_unsafe_h, errors_as_objects: true)

        if errors.any?
          StatsD.increment("#{STATSD_KEY_PREFIX}.schema_validation_error")
          render(
            json:   { errors: errors.map { |e| e[:message] } },
            status: :unprocessable_entity
          )
        end
      end

      def submission_params
        params.require(:enrollment_certification).permit(
          sco_authorization:           %i[sco_user_id sco_attestation],
          certification_type_info:     [:certification_type],
          institution_information:     %i[
            facility_code institution_name address_line1 address_line2
            city state zip_code institution_type yellow_ribbon_participant
          ],
          student_identification:      %i[
            identifier_type student_identifier student_ssn student_va_file_number
            student_first_name student_middle_name student_last_name student_suffix
            student_date_of_birth student_email_address
          ],
          benefit_chapter:             %i[chapter active_duty_status],
          enrollment_period:           %i[
            training_period_begin_date training_period_end_date
            prior_certification_reference_number effective_date_of_change
          ],
          program_information:         [
            :program_major_name, :degree_certificate_level, :standard_length_of_program,
            :standard_length_other,
            special_program_flags: %i[
              licensing_certification_program correspondence
              independent_study coop_training
            ]
          ],
          credit_hours_training_time:  %i[
            credit_type hours_enrolled full_time_standard
            training_time_classification rate_of_pursuit
          ],
          tuition_fees:                %i[
            tuition_charged mandatory_fees_charged total_tuition_and_fees
            itemized_fee_description non_resident_student
          ],
          yellow_ribbon:               %i[
            school_yellow_ribbon_contribution va_yellow_ribbon_matching_amount
            yellow_ribbon_agreement_reference_number
          ],
          prior_certification_changes: [
            :change_description, :course_change_date, :updated_hours_enrolled,
            :updated_training_time_classification, :mitigating_circumstances_apply,
            :mitigating_circumstances_description,
            types_of_change: %i[
              added_courses dropped_courses training_time_reclassification
              tuition_fee_correction program_change other
            ]
          ],
          termination_information:     %i[
            termination_reason last_date_of_attendance official_withdrawal_date
            non_punitive_grades_received mitigating_circumstances_apply
            mitigating_circumstances_description
          ],
          sco_certification:           %i[
            sco_first_name sco_last_name sco_title sco_phone_number
            sco_email_address sco_fax_number certification_attestation
            date_of_certification
          ]
        )
      end
    end
  end
end