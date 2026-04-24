# frozen_string_literal: true

module SimpleFormsApi
  class VBA102850D < BaseForm
    STATS_KEY = 'api.simple_forms_api.10_2850d'

    # ---------------------------------------------------------------------------
    # metadata
    #
    # Returns a hash of descriptive metadata used by the shared uploads pipeline
    # (SimpleFormsApiSubmission::MetadataValidator, benefits-intake service, and
    # audit/monitoring tooling).  Fields mirror what other health/VBA forms in
    # this module provide.
    # ---------------------------------------------------------------------------
    def metadata
      {
        form_number:      '10-2850D',
        veteran_first_name: notification_first_name,
        veteran_last_name:  notification_last_name,
        zip_code:           applicant_zip,
        receive_date:       @signature_date.iso8601,
        source:             'VA Platform Digital Forms',
        payload_version:    '1',
        station_id:         data.dig('vaTrainingFacilityId').presence || 'UNKNOWN'
      }
    end

    # ---------------------------------------------------------------------------
    # desired_stamps
    #
    # 10-2850D uses the standard Lighthouse benefits-intake PDF pipeline.
    # No additional pre-submission Prawn stamps are required beyond the
    # submission_date_stamps below.  Return an empty array per the base pattern
    # (see vba_21686_c.rb).
    # ---------------------------------------------------------------------------
    def desired_stamps
      []
    end

    # ---------------------------------------------------------------------------
    # submission_date_stamps
    #
    # Overlay stamps applied to page 0 of the generated PDF after field
    # population.  Mirrors the placement style used by vba_21686_c.rb.
    # Coordinates are provisional — verify against the AUG 2024 fillable PDF
    # once the template is committed to lib/pdf_fill/forms/.
    # ---------------------------------------------------------------------------
    def submission_date_stamps(timestamp = Time.current)
      [
        date_box_stamp(710, 'Submitted Via: VA.gov Digital Form'),
        date_box_stamp(695, 'VA Form 10-2850D Health Professions Trainee'),
        date_box_stamp(680, "#{timestamp.utc.strftime('%I:%M %p')} UTC #{timestamp.utc.strftime('%Y-%m-%d')}"),
        date_box_stamp(665, 'Electronically signed with a Login.gov'),
        date_box_stamp(650, 'identity-verified (IAL2) account.')
      ]
    end

    # ---------------------------------------------------------------------------
    # BaseForm overrides
    #
    # 10-2850D uses flat camelCase keys at the top level of `data` (per the
    # Architecture Intent Section 3.3 payload schema) rather than the nested
    # veteran_full_name / veteran hash that VBA forms use.  Override the two
    # BaseForm accessor helpers so the shared UploadsController notification
    # path still works correctly.
    # ---------------------------------------------------------------------------
    def notification_first_name
      data['firstName'].presence || data.dig('applicantInformation', 'firstName')
    end

    def notification_last_name
      data['lastName'].presence || data.dig('applicantInformation', 'lastName')
    end

    def notification_email_address
      data['primaryEmail'].presence || data.dig('applicantInformation', 'primaryEmail')
    end

    # ---------------------------------------------------------------------------
    # should_send_to_point_of_contact?
    #
    # 10-2850D DEO notification is handled separately via the DeoNotificationJob
    # (Phase 2 VANotify integration).  For MVP the shared point-of-contact
    # notification path is not used.
    # ---------------------------------------------------------------------------
    def should_send_to_point_of_contact?
      false
    end

    private

    # ---------------------------------------------------------------------------
    # applicant_zip
    #
    # Resolves ZIP code from either the flat camelCase top-level payload or the
    # nested applicantInformation chapter object.  Returns a safe default so
    # MetadataValidator does not raise on a missing key.
    # ---------------------------------------------------------------------------
    def applicant_zip
      data['presentAddressZip'].presence ||
        data.dig('applicantInformation', 'presentAddressZip').presence ||
        '00000'
    end

    # ---------------------------------------------------------------------------
    # date_box_stamp
    #
    # Builds a single stamp hash in the format expected by the shared PDF stamper.
    # Coordinates follow the same [x, y] convention used in vba_21686_c.rb.
    # ---------------------------------------------------------------------------
    def date_box_stamp(y_coordinate, text)
      {
        coords:    [395, y_coordinate],
        text:      text,
        page:      0,
        font_size: 10
      }
    end
  end
end