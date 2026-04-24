# frozen_string_literal: true

module SimpleFormsApi
  class VBA102850E < BaseForm
    STATS_KEY = 'api.simple_forms_api.10_2850e'

    # Returns PDF stamp metadata used by the benefits-intake pipeline to
    # identify the form and route it correctly.
    #
    # NOTE: VA Form 10-2850e is a VHA credentialing form — not a VBA benefits
    # claim. The `benefits_intake_service` pipeline is used here only for the
    # shared PDF-packaging and upload infrastructure. Actual downstream routing
    # to VetPro / HR Connect is handled post-intake by VHA operations staff
    # until a direct VetPro/HR Connect API integration is available.
    #
    # ⚠️ The OMB control number and veteran_icn values below are placeholders
    # that MUST be confirmed against the official form PDF and VHA OHRM before
    # this model is used in a production submission pipeline.
    def metadata
      {
        # ⚠️ OMB control number unverified — must be confirmed from official form PDF
        'veteranFirstName' => applicant_first_name,
        'veteranLastName'  => applicant_last_name,
        'fileNumber'       => applicant_ssn_last_four,
        'zipCode'          => applicant_zip_code,
        'source'           => 'VA Platform Digital Forms',
        'docType'          => '10-2850e',
        'businessLine'     => 'VHA'
      }
    end

    # Returns an array of PDF overlay stamp configurations. Currently empty
    # because the authoritative VA Form 10-2850e PDF has not been retrieved
    # and its coordinate grid is unverified.
    #
    # ⚠️ Once the official PDF is obtained, add checkbox stamps and any
    # field overlay stamps here following the date_box_stamp pattern below.
    def desired_stamps
      []
    end

    # Returns an array of date/submission-provenance stamp configurations
    # applied to page 0 of the generated PDF. Coordinates are provisional
    # and MUST be adjusted against the actual form PDF layout.
    #
    # ⚠️ All y-coordinates below are illustrative placeholders copied from
    # comparable VBA forms. They must be verified against the real PDF
    # before any print/upload testing.
    def submission_date_stamps(timestamp = Time.current)
      [
        date_box_stamp(710, 'Submitted Via: VA.gov Digital Form'),
        date_box_stamp(695, 'VA Form 10-2850e — Healthcare Professional'),
        date_box_stamp(680, 'Credentialing Application'),
        date_box_stamp(665, "#{timestamp.utc.strftime('%I:%M %p')} UTC #{timestamp.utc.strftime('%Y-%m-%d')}"),
        date_box_stamp(650, 'Signee signed with an identity-verified'),
        date_box_stamp(635, 'account (IAL2 / LOA3).')
      ]
    end

    # ── Notification helpers ──────────────────────────────────────────────────

    # Override BaseForm#notification_first_name to read from
    # personalInformation rather than the standard veteran_full_name path.
    def notification_first_name
      data.dig('personalInformation', 'firstName')
    end

    # Override BaseForm#notification_email_address to read from
    # contactInformation.professionalEmail for this credentialing form.
    def notification_email_address
      data.dig('contactInformation', 'professionalEmail')
    end

    # ── Attestation convenience readers ──────────────────────────────────────

    def certifies_accuracy?
      data.dig('attestation', 'certifiesAccuracy') == true
    end

    def electronic_signature_name
      data.dig('attestation', 'electronicSignatureName')
    end

    def signature_date_value
      data.dig('attestation', 'signatureDate')
    end

    # ── Appointment convenience readers ──────────────────────────────────────

    def target_facility_id
      data.dig('appointmentDetails', 'facilityId')
    end

    def application_type
      data['applicationType']
    end

    # ── Adverse history helpers ───────────────────────────────────────────────

    # Returns true if the applicant disclosed any adverse history that
    # requires additional VHA HR review.
    def has_adverse_disclosures?
      adverse = data['adverseHistory'] || {}

      adverse.dig('adverseLicensureActions', 'hasAdverseLicensureActions') == true ||
        adverse.dig('malpracticeHistory', 'hasMalpracticeHistory') == true ||
        adverse.dig('clinicalPrivilegesAdverse', 'hasAdversePrivilegesHistory') == true ||
        adverse.dig('deaRegistrationAdverse', 'hasAdverseDeaHistory') == true ||
        adverse.dig('criminalHistory', 'hasFelonyConviction') == true ||
        adverse.dig('criminalHistory', 'hasMisdemeanorConviction') == true
    end

    # Returns true if the applicant indicated they are currently on the
    # HHS OIG / SAM.gov federal exclusion list. Submissions MUST NOT be
    # forwarded to VetPro / HR Connect when this flag is set.
    def federally_excluded?
      data.dig('adverseHistory', 'federalExclusion', 'isCurrentlyExcluded') == true
    end

    private

    # ── Private helpers ───────────────────────────────────────────────────────

    def applicant_first_name
      data.dig('personalInformation', 'firstName') || ''
    end

    def applicant_last_name
      data.dig('personalInformation', 'lastName') || ''
    end

    # Returns the last four digits of the SSN for metadata routing.
    # The full SSN is never surfaced in metadata or logs.
    def applicant_ssn_last_four
      ssn = data.dig('personalInformation', 'ssn').to_s.gsub(/\D/, '')
      ssn.length >= 4 ? ssn.last(4) : ''
    end

    def applicant_zip_code
      data.dig('contactInformation', 'homeAddress', 'zipCode') || ''
    end

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