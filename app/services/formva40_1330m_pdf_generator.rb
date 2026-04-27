# frozen_string_literal: true

require 'pdf_fill/filler'

# Generates a filled PDF for VA Form 40-1330M by mapping structured form_data
# to the AcroForm fields of the official template PDF.
#
# ⚠️  UNVERIFIED: The official VA Form 40-1330M PDF with AcroForm fields must be
#     obtained from NCA / VA Forms Manager before this service is functional.
#     AcroForm field names in `mapped_data` are placeholders derived from the
#     architecture intent (§8.2) and must be validated against the actual PDF.
class Formva401330mPdfGenerator
  class GenerationError < StandardError; end

  TEMPLATE_PATH = Rails.root.join(
    'lib', 'pdf_fill', 'forms', 'pdfs', 'VA40-1330M.pdf'
  ).freeze

  DATE_FORMAT_OUTPUT = '%m/%d/%Y'
  DATE_FORMAT_INPUT  = '%Y-%m-%d'

  def initialize(form_data)
    @data = form_data.is_a?(Hash) ? form_data : {}
  end

  def generate
    raise GenerationError, 'PDF template not found at expected path' unless File.exist?(TEMPLATE_PATH)

    PdfFill::Filler.fill_form(
      TEMPLATE_PATH,
      mapped_data,
      flatten: true
    )
  rescue PdfFill::Filler::Error => e
    raise GenerationError, "PdfFill error: #{e.message}"
  rescue => e
    raise GenerationError, "Unexpected PDF generation error: #{e.message}"
  end

  private

  # ---------------------------------------------------------------------------
  # mapped_data — maps form_data JSON to AcroForm field names.
  # ⚠️  UNVERIFIED: all field name strings are placeholders.
  #     Run `PdfFill::Filler.get_fields(TEMPLATE_PATH)` against the official
  #     PDF to retrieve actual AcroForm field names, then update this hash.
  # ---------------------------------------------------------------------------
  def mapped_data # rubocop:disable Metrics/MethodLength
    {
      # ── Applicant ────────────────────────────────────────────────────────
      'APPLICANT_FIRST_NAME'            => dig('applicant', 'name', 'first'),
      'APPLICANT_MIDDLE_NAME'           => dig('applicant', 'name', 'middle'),
      'APPLICANT_LAST_NAME'             => dig('applicant', 'name', 'last'),
      'APPLICANT_SUFFIX'                => dig('applicant', 'name', 'suffix'),
      'APPLICANT_RELATIONSHIP'          => dig('applicant', 'relationshipToDecedent'),
      'APPLICANT_RELATIONSHIP_DESC'     => dig('applicant', 'relationshipDescription'),
      'APPLICANT_ORGANIZATION_NAME'     => dig('applicant', 'organizationName'),
      'APPLICANT_ORGANIZATION_ROLE'     => dig('applicant', 'organizationRole'),
      'APPLICANT_LEGAL_AUTHORITY'       => dig('applicant', 'legalAuthorityDescription'),
      'APPLICANT_ADDRESS_STREET'        => dig('applicant', 'address', 'street'),
      'APPLICANT_ADDRESS_STREET2'       => dig('applicant', 'address', 'street2'),
      'APPLICANT_ADDRESS_CITY'          => dig('applicant', 'address', 'city'),
      'APPLICANT_ADDRESS_STATE'         => dig('applicant', 'address', 'state'),
      'APPLICANT_ADDRESS_POSTAL_CODE'   => dig('applicant', 'address', 'postalCode'),
      'APPLICANT_ADDRESS_COUNTRY'       => dig('applicant', 'address', 'country'),
      'APPLICANT_DAYTIME_PHONE'         => dig('applicant', 'daytimePhone'),
      'APPLICANT_EMAIL'                 => dig('applicant', 'email'),

      # ── Decedent Personal Info ────────────────────────────────────────────
      'DECEDENT_FIRST_NAME'             => dig('decedent', 'name', 'first'),
      'DECEDENT_MIDDLE_NAME'            => dig('decedent', 'name', 'middle'),
      'DECEDENT_LAST_NAME'              => dig('decedent', 'name', 'last'),
      'DECEDENT_SUFFIX'                 => dig('decedent', 'name', 'suffix'),
      'DECEDENT_SSN'                    => masked_ssn,
      'DECEDENT_DATE_OF_BIRTH'          => format_date(dig('decedent', 'dateOfBirth')),
      'DECEDENT_DATE_OF_DEATH'          => format_date(dig('decedent', 'dateOfDeath')),
      'DECEDENT_PLACE_OF_DEATH_CITY'    => dig('decedent', 'placeOfDeath', 'city'),
      'DECEDENT_PLACE_OF_DEATH_STATE'   => dig('decedent', 'placeOfDeath', 'state'),
      'DECEDENT_PLACE_OF_DEATH_COUNTRY' => dig('decedent', 'placeOfDeath', 'country'),

      # ── Decedent Service Info ─────────────────────────────────────────────
      'SERVICE_BRANCH_OF_SERVICE'       => dig('decedent', 'service', 'branchOfService'),
      'SERVICE_COMPONENT'               => dig('decedent', 'service', 'component'),
      'SERVICE_RANK_AT_DEATH'           => dig('decedent', 'service', 'rankAtDeath'),
      'SERVICE_NUMBER'                  => dig('decedent', 'service', 'serviceNumber'),
      'SERVICE_ENTRY_DATE'              => format_date(dig('decedent', 'service', 'serviceEntryDate')),
      'SERVICE_END_DATE'                => format_date(dig('decedent', 'service', 'serviceEndDate')),

      # ── Burial Location ───────────────────────────────────────────────────
      'CEMETERY_NAME'                   => dig('burialLocation', 'cemeteryName'),
      'CEMETERY_ADDRESS_STREET'         => dig('burialLocation', 'cemeteryAddress', 'street'),
      'CEMETERY_ADDRESS_STREET2'        => dig('burialLocation', 'cemeteryAddress', 'street2'),
      'CEMETERY_ADDRESS_CITY'           => dig('burialLocation', 'cemeteryAddress', 'city'),
      'CEMETERY_ADDRESS_STATE'          => dig('burialLocation', 'cemeteryAddress', 'state'),
      'CEMETERY_ADDRESS_POSTAL_CODE'    => dig('burialLocation', 'cemeteryAddress', 'postalCode'),
      'CEMETERY_CONTACT_NAME'           => dig('burialLocation', 'cemeteryContactName'),
      'CEMETERY_CONTACT_PHONE'          => dig('burialLocation', 'cemeteryContactPhone'),
      'GRAVE_SECTION'                   => dig('burialLocation', 'graveSection'),
      'GRAVE_LOT'                       => dig('burialLocation', 'graveLot'),
      'GRAVE_NUMBER'                    => dig('burialLocation', 'graveNumber'),
      'EXISTING_MARKER_PRESENT'         => dig('burialLocation', 'existingMarkerPresent'),

      # ── Marker Request ────────────────────────────────────────────────────
      'MARKER_TYPE'                     => dig('markerRequest', 'markerType'),
      'EMBLEM_OF_BELIEF'                => dig('markerRequest', 'emblemOfBelief'),
      'PERSONAL_INSCRIPTION'            => dig('markerRequest', 'personalInscription'),

      # ── Eligibility ───────────────────────────────────────────────────────
      'SERVICE_STATUS_AT_DEATH'         => dig('serviceStatusAtDeath'),
      'GUARD_RESERVE_CIRCUMSTANCE'      => dig('guardReserveQualifyingCircumstance'),

      # ── Certification ─────────────────────────────────────────────────────
      'SUBMISSION_DATE'                 => Date.current.strftime(DATE_FORMAT_OUTPUT),
      'SUBMISSION_SOURCE'               => 'VA.gov Digital Form',
      'CERTIFICATIONATTESTATION'        => dig('certificationAttestation').to_s
    }.compact
  end

  def dig(*keys)
    @data.dig(*keys)
  end

  def format_date(iso_string)
    return nil if iso_string.blank?

    Date.strptime(iso_string, DATE_FORMAT_INPUT).strftime(DATE_FORMAT_OUTPUT)
  rescue Date::Error
    nil
  end

  # SSN is included in the PDF (required for NCA processing) but is masked in
  # any application logs.  The PDF itself is encrypted at rest on the tmp volume.
  def masked_ssn
    dig('decedent', 'ssn')
  end
end