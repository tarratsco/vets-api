# frozen_string_literal: true

require 'pdf_fill/filler'

# Assembles a filled VA Form 27-2008 PDF from submission form_data.
#
# Wraps PdfFill::Filler with the 27-2008-specific field mapping.
# The output is a temporary file on disk; the caller is responsible
# for cleaning it up after submission to Benefits Intake API.
#
# Usage:
#   path = Form27_2008PdfGenerator.new(submission.form_data).generate
#   # => '/tmp/form27_2008_<uuid>.pdf'
class Form27_2008PdfGenerator
  FORM_ID     = '27-2008'
  TEMPLATE_ID = 'vba_27_2008'

  BRANCH_TO_FIELD_MAP = {
    'army'            => 'branchArmy',
    'navy'            => 'branchNavy',
    'airForce'        => 'branchAirForce',
    'spaceForce'      => 'branchSpaceForce',
    'marineCorps'     => 'branchMarineCorps',
    'coastGuard'      => 'branchCoastGuard',
    'usphs'           => 'branchUSPHS',
    'noaa'            => 'branchNOAA',
    'selectedReserve' => 'branchSelectedReserve',
    'other'           => 'branchOther'
  }.freeze

  def initialize(form_data)
    @data = form_data.is_a?(Hash) ? form_data : JSON.parse(form_data.to_s)
  end

  # Generates the filled PDF and returns the temp file path.
  # Raises PdfFill::Errors::PdfFormError on generation failure.
  def generate
    StatsD.increment('api.form27_2008.pdf_generation.attempt')
    start_time = Time.current

    filled_data = build_pdf_data
    path        = PdfFill::Filler.fill_form_by_type(filled_data, TEMPLATE_ID)

    elapsed_ms = ((Time.current - start_time) * 1000).round
    StatsD.timing('api.form27_2008.pdf_generation.duration', elapsed_ms)
    StatsD.increment('api.form27_2008.pdf_generation.success')

    Rails.logger.info(
      message:    'form27_2008_pdf_generated',
      path:       path,
      duration_ms: elapsed_ms
    )

    path
  rescue => e
    StatsD.increment('api.form27_2008.pdf_generation.error',
                     tags: ["error_class:#{e.class}"])
    Rails.logger.error(
      message:     'form27_2008_pdf_generation_error',
      error:       e.message,
      error_class: e.class.to_s
    )
    raise
  end

  private

  def veteran_information
    @data['veteranInformation'] || {}
  end

  def service_information
    @data['serviceInformation'] || {}
  end

  def eligibility
    @data['eligibility'] || {}
  end

  def flag_recipient
    @data['flagRecipient'] || {}
  end

  def applicant_data
    @data['applicant'] || {}
  end

  # Builds the flat hash that PdfFill::Filler expects, mirroring the
  # AcroForm field names defined in lib/pdf_fill/forms/va27_2008.rb.
  # NOTE: AcroForm field key names are illustrative until OQ-08 is resolved
  # and the actual MAY 2024 PDF is analyzed with `pdftk dump_data_fields`.
  def build_pdf_data
    pdf_data = {}

    # Items 1, 2 — Veteran name
    pdf_data['veteranFirstName']         = veteran_information['firstName'].to_s
    pdf_data['veteranMiddleName']        = veteran_information['middleName'].to_s
    pdf_data['veteranLastName']          = veteran_information['lastName'].to_s
    pdf_data['veteranMaidenOrOtherName'] = veteran_information['maidenOrOtherName'].to_s

    # Items 3, 4, 5 — Identification numbers
    pdf_data['vaFileNumber']             = veteran_information['vaFileNumber'].to_s
    pdf_data['veteranSocialSecurityNumber'] = veteran_information['socialSecurityNumber'].to_s
    pdf_data['militaryServiceNumber']    = veteran_information['militaryServiceNumber'].to_s

    # Item 6 — Branch of Service checkboxes (array → individual boolean fields)
    branches = Array(service_information['branchOfService'])
    BRANCH_TO_FIELD_MAP.each do |branch_key, pdf_field|
      pdf_data[pdf_field] = branches.include?(branch_key)
    end

    # Items 7, 8 — Service dates
    pdf_data['dateEnteredActiveDuty']      = format_date(service_information['dateEnteredActiveDuty'])
    pdf_data['dateReleasedFromActiveDuty'] = format_date(service_information['dateReleasedFromActiveDuty'])

    # Items 9, 10, 11 — Veteran dates
    pdf_data['veteranDateOfBirth'] = format_date(veteran_information['dateOfBirth'])
    pdf_data['veteranDateOfDeath'] = format_date(veteran_information['dateOfDeath'])
    pdf_data['dateOfBurial']       = format_date(veteran_information['dateOfBurial'])

    # Item 12 — Place of burial
    pdf_data['placeOfBurialCemeteryName'] = veteran_information['placeOfBurialCemeteryName'].to_s
    pdf_data['placeOfBurialCity']         = veteran_information['placeOfBurialCity'].to_s
    pdf_data['placeOfBurialState']        = veteran_information['placeOfBurialState'].to_s

    # Item 13 — Documentation checkboxes
    doc_available = eligibility['documentationAvailable']
    pdf_data['documentationYes'] = doc_available == true
    pdf_data['documentationNo']  = doc_available == false

    # Item 14A, 14B — Flag recipient
    pdf_data['flagRecipientFullName']     = flag_recipient['recipientFullName'].to_s
    pdf_data['flagRecipientRelationship'] = build_recipient_relationship_text

    # Item 14C — Flag recipient address (combined per paper form layout)
    pdf_data['flagRecipientAddress'] = format_address(
      line1: flag_recipient['recipientAddressLine1'],
      line2: flag_recipient['recipientAddressLine2'],
      city:  flag_recipient['recipientCity'],
      state: flag_recipient['recipientState'],
      zip:   flag_recipient['recipientZip']
    )

    # Item 14D — Flag recipient phone
    pdf_data['flagRecipientPhone'] = format_phone(flag_recipient['recipientPhone'])

    # Item 15 — Remarks
    pdf_data['remarks'] = @data['remarks'].to_s

    # Item 16 — Electronic signature equivalent (see architecture intent OQ-04)
    applicant_name = [
      applicant_data['firstName'],
      applicant_data['middleName'],
      applicant_data['lastName']
    ].compact.join(' ')
    date_signed_formatted = format_date(@data['dateSigned'])
    pdf_data['applicantSignature'] =
      "#{applicant_name} — Electronically certified on #{date_signed_formatted} via VA.gov"

    # Item 17 — Applicant address
    pdf_data['applicantFirstName']  = applicant_data['firstName'].to_s
    pdf_data['applicantMiddleName'] = applicant_data['middleName'].to_s
    pdf_data['applicantLastName']   = applicant_data['lastName'].to_s
    pdf_data['applicantAddress'] = format_address(
      line1: applicant_data['addressLine1'],
      line2: applicant_data['addressLine2'],
      city:  applicant_data['city'],
      state: applicant_data['state'],
      zip:   applicant_data['zip']
    )

    # Item 18 — Applicant relationship to Veteran
    pdf_data['applicantRelationshipToVeteran'] = build_applicant_relationship_text

    # Item 19 — Date signed
    pdf_data['dateSigned'] = format_date(@data['dateSigned'])

    pdf_data
  end

  # Transforms YYYY-MM-DD → MM/DD/YYYY for PDF display.
  def format_date(date_string)
    return '' if date_string.blank?

    Date.parse(date_string).strftime('%m/%d/%Y')
  rescue ArgumentError, TypeError
    date_string.to_s
  end

  # Formats a 10-digit phone number as (NXX) NXX-XXXX.
  def format_phone(phone)
    return '' if phone.blank?

    digits = phone.gsub(/\D/, '')
    return phone unless digits.length == 10

    "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
  end

  # Combines address components into a single multi-line string
  # matching the paper form's single combined address field.
  def format_address(line1:, line2:, city:, state:, zip:)
    parts = [line1, line2, "#{city}, #{state} #{zip}"].compact_blank
    parts.join("\n")
  end

  def build_recipient_relationship_text
    relationship = flag_recipient['recipientRelationship'].to_s
    return flag_recipient['recipientRelationshipOther'].to_s if relationship == 'other'

    relationship.humanize
  end

  def build_applicant_relationship_text
    relationship = applicant_data['relationshipToVeteran'].to_s
    return applicant_data['relationshipToVeteranOther'].to_s if relationship == 'otherAuthorizedRepresentative'

    relationship.humanize
  end
end