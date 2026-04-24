# frozen_string_literal: true

module PdfFill
  module Forms
    # PDF field mapping for VA Form 22-1999b — Enrollment Change / Termination Certification.
    #
    # ⚠️  ALL AcroForm field names below are PLACEHOLDERS.
    # The official PDF template must be obtained from va.gov/find-forms/ (see Architecture Intent OQ-3).
    # After obtaining the PDF, run:
    #   pdftk VA22-1999b.pdf dump_data_fields output field_names.txt
    # and replace every placeholder field name with the extracted AcroForm name.
    #
    # The PDF template must be placed at:
    #   lib/pdf_fill/forms/pdftk/VA22-1999b.pdf
    class Va221999b
      ITERATOR = PdfFill::HashConverter::ITERATOR

      ENROLLMENT_TYPE_LABELS = {
        'full_time'            => 'Full Time',
        'three_quarter_time'   => 'Three Quarter Time',
        'half_time'            => 'Half Time',
        'less_than_half_time'  => 'Less Than Half Time'
      }.freeze

      BENEFIT_CHAPTER_LABELS = {
        'chapter_33'   => 'Chapter 33 (Post-9/11 GI Bill)',
        'chapter_30'   => 'Chapter 30 (MGIB Active Duty)',
        'chapter_35'   => 'Chapter 35 (DEA)',
        'chapter_1606' => 'Chapter 1606 (MGIB Selected Reserve)',
        'chapter_1607' => 'Chapter 1607 (REAP)'
      }.freeze

      TYPE_OF_CHANGE_LABELS = {
        'full_termination'      => 'Full Termination',
        'partial_withdrawal'    => 'Partial Withdrawal',
        'credit_hour_reduction' => 'Credit Hour Reduction',
        'correction'            => 'Correction'
      }.freeze

      # Mapping: JSON payload key path → PDF AcroForm field name
      # Field names are placeholders — must be replaced after PDF extraction.
      KEY_MAP = {
        # Chapter 1 — Institution
        'facility_code'      => 'form1[0].#subform[0].FacilityCode[0]',
        'institution_name'   => 'form1[0].#subform[0].InstitutionName[0]',
        'institution_street' => 'form1[0].#subform[0].InstitutionStreet[0]',
        'institution_city'   => 'form1[0].#subform[0].InstitutionCity[0]',
        'institution_state'  => 'form1[0].#subform[0].InstitutionState[0]',
        'institution_zip'    => 'form1[0].#subform[0].InstitutionZip[0]',

        # Chapter 1 — SCO Contact
        'sco_first_name'   => 'form1[0].#subform[0].SCOFirstName[0]',
        'sco_last_name'    => 'form1[0].#subform[0].SCOLastName[0]',
        'sco_title'        => 'form1[0].#subform[0].SCOTitle[0]',
        'sco_phone'        => 'form1[0].#subform[0].SCOPhone[0]',
        'sco_email'        => 'form1[0].#subform[0].SCOEmail[0]',

        # Chapter 2 — Student Identification
        'student_first_name'          => 'form1[0].#subform[0].StudentFirstName[0]',
        'student_last_name'           => 'form1[0].#subform[0].StudentLastName[0]',
        'student_ssn_last4'           => 'form1[0].#subform[0].StudentSSNLast4[0]',
        'student_va_file_number'      => 'form1[0].#subform[0].StudentVAFileNumber[0]',
        'benefit_chapter'             => 'form1[0].#subform[0].BenefitChapter[0]',

        # Chapter 2 — Prior Certification
        'original_cert_begin_date'    => 'form1[0].#subform[0].OrigCertBeginDate[0]',
        'original_cert_end_date'      => 'form1[0].#subform[0].OrigCertEndDate[0]',
        'original_credit_hours'       => 'form1[0].#subform[0].OrigCreditHours[0]',
        'original_enrollment_type'    => 'form1[0].#subform[0].OrigEnrollmentType[0]',

        # Chapter 3 — Change Details
        'type_of_change'              => 'form1[0].#subform[0].TypeOfChange[0]',
        'effective_date_of_change'    => 'form1[0].#subform[0].EffectiveDateOfChange[0]',
        'last_date_of_attendance'     => 'form1[0].#subform[0].LastDateOfAttendance[0]',
        'new_credit_hours'            => 'form1[0].#subform[0].NewCreditHours[0]',
        'new_enrollment_type'         => 'form1[0].#subform[0].NewEnrollmentType[0]',
        'reason_for_change'           => 'form1[0].#subform[0].ReasonForChange[0]',
        'mitigating_circumstances_known' => 'form1[0].#subform[0].MitigatingCircumstancesKnown[0]',
        'mitigating_circumstances_narrative' => 'form1[0].#subform[0].MitigatingCircumstancesNarrative[0]',
        'correction_items_text'       => 'form1[0].#subform[0].CorrectionItems[0]',
        'late_submission_explanation' => 'form1[0].#subform[0].LateSubmissionExplanation[0]',

        # Attestation
        'sco_certification_attested'  => 'form1[0].#subform[0].SCOCertification[0]'
      }.freeze

      # Builds the PDF field hash consumed by PdfFill::Filler.
      # Accepts the raw form_data hash (from form model's #data attribute).
      def merge_fields(options)
        form_data = options[:form_data] || {}
        form      = SimpleFormsApi::VBA221999b.new(form_data)

        flat = flatten_form_data(form)

        KEY_MAP.each_with_object({}) do |(logical_key, pdf_field), hash|
          value = flat[logical_key]
          hash[pdf_field] = transform(logical_key, value)
        end
      end

      private

      # Flatten the nested chapter structure into a single-level hash
      # keyed by the logical names used in KEY_MAP.
      def flatten_form_data(form)
        institution_addr = form.data.dig('institutionAndScoInformation', 'institutionAddress') ||
                           form.data.dig('institution_and_sco_information', 'institution_address') || {}
        updated          = form.updated_enrollment_details
        mitigation       = form.mitigating_circumstances

        {
          'facility_code'                      => form.facility_code,
          'institution_name'                   => form.institution_name,
          'institution_street'                 => institution_addr['street'],
          'institution_city'                   => institution_addr['city'],
          'institution_state'                  => institution_addr['state'],
          'institution_zip'                    => institution_addr['zip'],
          'sco_first_name'                     => form.sco_first_name,
          'sco_last_name'                      => form.sco_last_name,
          'sco_title'                          => form.data.dig('institutionAndScoInformation', 'scoTitle'),
          'sco_phone'                          => format_phone(form.sco_phone),
          'sco_email'                          => form.sco_email,
          'student_first_name'                 => form.student_first_name,
          'student_last_name'                  => form.student_last_name,
          'student_ssn_last4'                  => form.student_ssn.to_s.last(4),
          'student_va_file_number'             => form.student_va_file_number,
          'benefit_chapter'                    => BENEFIT_CHAPTER_LABELS[form.benefit_chapter],
          'original_cert_begin_date'           => form.original_cert_begin_date,
          'original_cert_end_date'             => form.original_cert_end_date,
          'original_credit_hours'              => form.original_credit_hours,
          'original_enrollment_type'           => ENROLLMENT_TYPE_LABELS[form.original_enrollment_type],
          'type_of_change'                     => TYPE_OF_CHANGE_LABELS[form.type_of_change],
          'effective_date_of_change'           => form.effective_date_of_change,
          'last_date_of_attendance'            => form.last_date_of_attendance,
          'new_credit_hours'                   => updated['newCreditHours'] || updated['new_credit_hours'],
          'new_enrollment_type'                => ENROLLMENT_TYPE_LABELS[updated['newEnrollmentType'] || updated['new_enrollment_type']],
          'reason_for_change'                  => form.reason_for_change,
          'mitigating_circumstances_known'     => form.mitigating_circumstances_known,
          'mitigating_circumstances_narrative' => form.mitigating_circumstances_narrative,
          'correction_items_text'              => form.correction_items.join(', '),
          'late_submission_explanation'        => form.late_submission_explanation,
          'sco_certification_attested'         => form.sco_certification_attested
        }
      end

      def transform(key, value)
        return nil if value.nil?

        case key
        when /date/
          format_date(value)
        when 'sco_certification_attested'
          value == true || value == 'true' ? 'Yes' : nil
        else
          value.to_s.presence
        end
      end

      def format_date(iso_date)
        return nil if iso_date.blank?

        Date.parse(iso_date.to_s).strftime('%m/%d/%Y')
      rescue ArgumentError, TypeError
        nil
      end

      def format_phone(raw_phone)
        return nil if raw_phone.blank?

        digits = raw_phone.to_s.gsub(/\D/, '')
        return raw_phone if digits.length != 10

        "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
      end
    end
  end
end