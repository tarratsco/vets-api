# frozen_string_literal: true

module SimpleFormsApi
  class VBA107959E < BaseForm
    STATS_KEY = 'api.simple_forms_api.10_7959e'

    # ---------------------------------------------------------------------------
    # metadata
    #
    # Returns a hash of metadata consumed by the Benefits Intake submission
    # pipeline (and / or the interim PDF-delivery worker). Keys mirror the
    # shape expected by SimpleFormsApiSubmission::MetadataValidator.
    #
    # Fields pulled from the submitted form payload (data hash):
    #   data['patient']       — Section I  (beneficiary child)
    #   data['sponsor']       — Section II (qualifying Veteran)
    #   data['programSelection']['program'] — 'spina-bifida' | 'cwvv'
    #   data['claimType']     — array of claimed expense types
    #   data['certification'] — Section IV signature block
    # ---------------------------------------------------------------------------
    def metadata
      patient   = data['patient'] || {}
      sponsor   = data['sponsor'] || {}
      program   = data.dig('programSelection', 'program') || ''
      claim_type = Array(data['claimType'])

      {
        # Claimant identity (patient / beneficiary child)
        'veteranFirstName' => patient['firstName'],
        'veteranLastName'  => patient['lastName'],
        'fileNumber'       => nil, # OIVC program — no VA file number applicable

        # Sponsor (qualifying Veteran) identity — stored for OIVC routing
        'sponsorFirstName' => sponsor['firstName'],
        'sponsorLastName'  => sponsor['lastName'],

        # Program and claim classification
        'programSelection' => program,
        'claimType'        => claim_type,

        # Submission metadata
        'receiveDt'        => receive_date,
        'uuid'             => SecureRandom.uuid,
        'zipCode'          => patient.dig('address', 'zipCode'),

        # Source system identifier used by Benefits Intake routing
        'source'           => 'VA Platform Digital Forms',
        'docType'          => '10-7959E'
      }
    end

    # ---------------------------------------------------------------------------
    # desired_stamps
    #
    # Returns an array of text-stamp configurations to be applied to the
    # generated PDF before delivery to OIVC. Each entry is a hash with:
    #   coords:    [x, y]  — lower-left origin in PDF points (72 pts / inch)
    #   text:      String  — stamp text
    #   page:      Integer — 0-indexed PDF page number
    #   font_size: Integer — point size
    #
    # For 10-7959E the program selection is stamped in the top margin of
    # page 1 so OIVC staff can immediately identify which sub-program the
    # claim belongs to without opening the form body.
    # ---------------------------------------------------------------------------
    def desired_stamps
      program_label = program_display_label

      [
        {
          coords:    [10, 785],
          text:      "Program: #{program_label}",
          page:      0,
          font_size: 10
        }
      ]
    end

    # ---------------------------------------------------------------------------
    # submission_date_stamps
    #
    # Returns an array of stamp configs that record submission provenance in a
    # dedicated box area of the PDF. This matches the pattern established by
    # VBA21686C and other forms that have a PDF backing.
    #
    # The y-coordinates below target the bottom-right margin of VA Form
    # 10-7959E (JUN 2025). Adjust after the AcroForm field audit confirms
    # the exact printable area dimensions of the production PDF.
    # ---------------------------------------------------------------------------
    def submission_date_stamps(timestamp = Time.current)
      [
        date_box_stamp(710, 'Submitted Via: VA.gov Digital Form'),
        date_box_stamp(695, 'VA Form 10-7959E (JUN 2025)'),
        date_box_stamp(680, "#{timestamp.utc.strftime('%I:%M %p')} UTC #{timestamp.utc.strftime('%Y-%m-%d')}"),
        date_box_stamp(665, 'Signee signed with an identity-verified'),
        date_box_stamp(650, 'account.')
      ]
    end

    # ---------------------------------------------------------------------------
    # notification_first_name
    #
    # Override BaseForm#notification_first_name to source the name from the
    # certification signer rather than a generic 'veteran_full_name' key.
    # The confirmation email should address the person who actually signed —
    # either the patient (adult beneficiary) or the representative
    # (parent/guardian).
    # ---------------------------------------------------------------------------
    def notification_first_name
      if data['certificationSigner'] == 'representative'
        data.dig('representative', 'firstName')
      else
        data.dig('patient', 'firstName')
      end
    end

    # ---------------------------------------------------------------------------
    # notification_email_address
    #
    # 10-7959E does not collect a claimant email address in the form payload
    # (the authenticated session provides the email for VA Notify). Return nil
    # so the uploads controller falls back to the authenticated user's
    # va_profile_email, consistent with how other forms that don't embed an
    # email field behave.
    # ---------------------------------------------------------------------------
    def notification_email_address
      nil
    end

    private

    # ---------------------------------------------------------------------------
    # receive_date
    #
    # Returns the current timestamp formatted as expected by Benefits Intake
    # metadata ('YYYY-MM-DD HH:MM:SS'). Uses the same Chicago timezone anchor
    # established by BaseForm#initialize for @signature_date consistency.
    # ---------------------------------------------------------------------------
    def receive_date
      Time.current.in_time_zone('America/Chicago').strftime('%Y-%m-%d %H:%M:%S')
    end

    # ---------------------------------------------------------------------------
    # program_display_label
    #
    # Converts the raw program selection string to a human-readable label for
    # use in PDF stamps and confirmation email subject lines.
    # ---------------------------------------------------------------------------
    def program_display_label
      case data.dig('programSelection', 'program')
      when 'spina-bifida'
        'Spina Bifida Health Care Benefits Program'
      when 'cwvv'
        'Children of Women Vietnam Veterans (CWVV) Program'
      else
        'Unknown Program'
      end
    end

    # ---------------------------------------------------------------------------
    # date_box_stamp
    #
    # Helper that builds a single stamp hash for submission_date_stamps.
    # x=395 targets the right half of a standard VA form (8.5" × 11" at
    # 72 pts/in = 612 pts wide; 395 ≈ 5.5" from left edge).
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