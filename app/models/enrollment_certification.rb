# app/models/enrollment_certification.rb
# frozen_string_literal: true

# == Schema Information
#
# Table name: enrollment_certifications
#
#  id                  :bigint           not null, primary key
#  user_uuid           :string           not null
#  saved_claim_id      :bigint
#  form_data           :jsonb            not null
#  status              :integer          default("pending"), not null
#  confirmation_number :string
#  submitted_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_enrollment_certifications_on_user_uuid            (user_uuid)
#  index_enrollment_certifications_on_status               (status)
#  index_enrollment_certifications_on_confirmation_number  (confirmation_number)
#

class EnrollmentCertification < ApplicationRecord
  include SetGuid

  FORM_ID = '22-1999'

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------

  enum status: {
    pending:    0,
    submitted:  1,
    processing: 2,
    success:    3,
    failed:     4,
    expired:    5
  }

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :saved_claim, optional: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :for_user,           ->(uuid) { where(user_uuid: uuid) }
  scope :pending_submission, -> { where(status: :pending) }
  scope :recently_submitted, -> { where(status: :success).order(submitted_at: :desc) }
  scope :needs_retry,        -> { where(status: :failed).where('updated_at < ?', 24.hours.ago) }
  scope :stale_pending,      -> { where(status: :pending).where('created_at < ?', 1.hour.ago) }

  # ---------------------------------------------------------------------------
  # Validations — structural
  # ---------------------------------------------------------------------------

  validates :user_uuid,  presence: true
  validates :form_data,  presence: true
  validates :status,     presence: true

  # ---------------------------------------------------------------------------
  # Validations — form data sections (mirror JSON Schema required array)
  # ---------------------------------------------------------------------------

  validate :validate_sco_verification
  validate :validate_certification_type_info
  validate :validate_student_information
  validate :validate_institution_information
  validate :validate_program_information
  validate :validate_enrollment_period
  validate :validate_credit_hours
  validate :validate_certifying_official

  # Optional sections — validated only when present
  validate :validate_tuition_and_fees,     if: :has_tuition_and_fees?
  validate :validate_yellow_ribbon,        if: :has_yellow_ribbon?
  validate :validate_credit_hour_override, if: :credit_hour_override_present?

  # ---------------------------------------------------------------------------
  # Delegated accessors for common form_data paths
  # ---------------------------------------------------------------------------

  def sco_verification        = form_data_section('scoVerification')
  def certification_type_info = form_data_section('certificationTypeInfo')
  def student_information     = form_data_section('studentInformation')
  def institution_information = form_data_section('institutionInformation')
  def program_information     = form_data_section('programInformation')
  def enrollment_period       = form_data_section('enrollmentPeriod')
  def credit_hours_section    = form_data_section('creditHours')
  def certifying_official     = form_data_section('certifyingOfficial')
  def tuition_and_fees        = form_data_section('tuitionAndFees')
  def yellow_ribbon           = form_data_section('yellowRibbon')

  # ---------------------------------------------------------------------------
  # Public helpers
  # ---------------------------------------------------------------------------

  def gi_chapter
    student_information&.dig('giChapter')
  end

  def chapter_33?
    gi_chapter == '33'
  end

  def facility_code
    sco_verification&.dig('facilityCode')
  end

  def student_full_name
    [
      student_information&.dig('firstName'),
      student_information&.dig('middleName'),
      student_information&.dig('lastName')
    ].compact.join(' ')
  end

  private

  # ---------------------------------------------------------------------------
  # Section presence guards
  # ---------------------------------------------------------------------------

  def has_tuition_and_fees?
    form_data.is_a?(Hash) && form_data['tuitionAndFees'].present?
  end

  def has_yellow_ribbon?
    form_data.is_a?(Hash) && form_data['yellowRibbon'].present?
  end

  def credit_hour_override_present?
    credit_hours_section&.dig('classificationOverridden') == true
  end

  # ---------------------------------------------------------------------------
  # Section validator helpers
  # ---------------------------------------------------------------------------

  def validate_sco_verification
    section = sco_verification
    return add_missing_section_error('scoVerification') unless section.is_a?(Hash)

    validate_presence(section, 'scoVerification', 'scoName')
    validate_presence(section, 'scoVerification', 'facilityCode')
    validate_facility_code_format(section['facilityCode'])
    validate_sco_name_format(section['scoName'])

    if section.key?('scoRole')
      valid_roles = %w[primary_certifying_official alternate_certifying_official secondary_certifying_official]
      unless valid_roles.include?(section['scoRole'])
        errors.add(:form_data, "scoVerification.scoRole must be one of: #{valid_roles.join(', ')}")
      end
    end
  end

  def validate_certification_type_info
    section = certification_type_info
    return add_missing_section_error('certificationTypeInfo') unless section.is_a?(Hash)

    validate_presence(section, 'certificationTypeInfo', 'certificationType')
    valid_types = %w[original amended termination]
    if section['certificationType'].present? && !valid_types.include?(section['certificationType'])
      errors.add(:form_data, "certificationTypeInfo.certificationType must be one of: #{valid_types.join(', ')}")
    end
  end

  def validate_student_information
    section = student_information
    return add_missing_section_error('studentInformation') unless section.is_a?(Hash)

    %w[firstName lastName dateOfBirth giChapter].each do |field|
      validate_presence(section, 'studentInformation', field)
    end

    # Either SSN or VA file number must be present
    unless section['ssn'].present? || section['vaFileNumber'].present?
      errors.add(:form_data, 'studentInformation must include either ssn or vaFileNumber')
    end

    validate_ssn_format(section['ssn'])                   if section['ssn'].present?
    validate_va_file_number_format(section['vaFileNumber']) if section['vaFileNumber'].present?
    validate_date_format(section['dateOfBirth'], 'studentInformation.dateOfBirth')
    validate_date_of_birth(section['dateOfBirth'])
    validate_name_field(section['firstName'],  'studentInformation.firstName')
    validate_name_field(section['lastName'],   'studentInformation.lastName')
    validate_name_field(section['middleName'], 'studentInformation.middleName') if section['middleName'].present?

    valid_chapters = %w[33 30 1606 35 32]
    if section['giChapter'].present? && !valid_chapters.include?(section['giChapter'])
      errors.add(:form_data, "studentInformation.giChapter must be one of: #{valid_chapters.join(', ')}")
    end
  end

  def validate_institution_information
    section = institution_information
    return add_missing_section_error('institutionInformation') unless section.is_a?(Hash)

    %w[facilityCode institutionName institutionType publicOrPrivate].each do |field|
      validate_presence(section, 'institutionInformation', field)
    end

    validate_facility_code_format(section['facilityCode'])

    if section['institutionName'].present?
      validate_string_length(section['institutionName'], 'institutionInformation.institutionName', 1, 200)
    end

    valid_types = %w[IHL NCD flight correspondence OJT]
    if section['institutionType'].present? && !valid_types.include?(section['institutionType'])
      errors.add(:form_data, "institutionInformation.institutionType must be one of: #{valid_types.join(', ')}")
    end

    valid_control = %w[public private]
    if section['publicOrPrivate'].present? && !valid_control.include?(section['publicOrPrivate'])
      errors.add(:form_data, "institutionInformation.publicOrPrivate must be one of: #{valid_control.join(', ')}")
    end

    if section['institutionAddress'].present?
      validate_address(section['institutionAddress'], 'institutionInformation.institutionAddress')
    end
  end

  def validate_program_information
    section = program_information
    return add_missing_section_error('programInformation') unless section.is_a?(Hash)

    validate_presence(section, 'programInformation', 'programName')
    validate_presence(section, 'programInformation', 'degreeLevel')

    if section['programName'].present?
      validate_string_length(section['programName'], 'programInformation.programName', 1, 200)
    end

    valid_levels = %w[associate bachelors masters doctoral certificate other]
    if section['degreeLevel'].present? && !valid_levels.include?(section['degreeLevel'])
      errors.add(:form_data, "programInformation.degreeLevel must be one of: #{valid_levels.join(', ')}")
    end

    if section['cipCode'].present?
      unless section['cipCode'].match?(/^\d{2}\.\d{4}$/)
        errors.add(:form_data, 'programInformation.cipCode must be in format XX.XXXX (e.g. 52.0201)')
      end
    end
  end

  def validate_enrollment_period
    section = enrollment_period
    return add_missing_section_error('enrollmentPeriod') unless section.is_a?(Hash)

    %w[enrollmentBeginDate enrollmentEndDate termType].each do |field|
      validate_presence(section, 'enrollmentPeriod', field)
    end

    validate_date_format(section['enrollmentBeginDate'], 'enrollmentPeriod.enrollmentBeginDate')
    validate_date_format(section['enrollmentEndDate'],   'enrollmentPeriod.enrollmentEndDate')
    validate_enrollment_dates(section['enrollmentBeginDate'], section['enrollmentEndDate'])

    valid_term_types = %w[semester quarter non_standard_session clock_hour_program]
    if section['termType'].present? && !valid_term_types.include?(section['termType'])
      errors.add(:form_data, "enrollmentPeriod.termType must be one of: #{valid_term_types.join(', ')}")
    end
  end

  def validate_credit_hours
    section = credit_hours_section
    return add_missing_section_error('creditHours') unless section.is_a?(Hash)

    %w[hoursEnrolled institutionFullTimeHours trainingTimeClassification].each do |field|
      validate_presence(section, 'creditHours', field)
    end

    validate_credit_hour_count(section['hoursEnrolled'],          'creditHours.hoursEnrolled')
    validate_credit_hour_count(section['institutionFullTimeHours'], 'creditHours.institutionFullTimeHours')

    if section['institutionFullTimeHours'].present? && section['institutionFullTimeHours'].to_i < 1
      errors.add(:form_data, 'creditHours.institutionFullTimeHours must be at least 1')
    end

    valid_classifications = %w[full_time three_quarter_time half_time less_than_half_time]
    if section['trainingTimeClassification'].present? && !valid_classifications.include?(section['trainingTimeClassification'])
      errors.add(:form_data, "creditHours.trainingTimeClassification must be one of: #{valid_classifications.join(', ')}")
    end
  end

  def validate_credit_hour_override
    section = credit_hours_section
    return unless section.is_a?(Hash)

    if section['overrideJustification'].blank?
      errors.add(:form_data, 'creditHours.overrideJustification is required when classificationOverridden is true')
    elsif section['overrideJustification'].length < 10
      errors.add(:form_data, 'creditHours.overrideJustification must be at least 10 characters')
    elsif section['overrideJustification'].length > 500
      errors.add(:form_data, 'creditHours.overrideJustification must be 500 characters or fewer')
    end
  end

  def validate_certifying_official
    section = certifying_official
    return add_missing_section_error('certifyingOfficial') unless section.is_a?(Hash)

    %w[officialName officialTitle officialPhone officialEmail attestationSigned].each do |field|
      validate_presence(section, 'certifyingOfficial', field)
    end

    validate_name_field(section['officialName'], 'certifyingOfficial.officialName')
    validate_string_length(section['officialTitle'], 'certifyingOfficial.officialTitle', 2, 100) if section['officialTitle'].present?
    validate_phone_format(section['officialPhone'])  if section['officialPhone'].present?
    validate_email_format(section['officialEmail'])  if section['officialEmail'].present?

    unless section['attestationSigned'] == true
      errors.add(:form_data, 'certifyingOfficial.attestationSigned must be true')
    end
  end

  def validate_tuition_and_fees
    section = tuition_and_fees
    return unless section.is_a?(Hash)

    validate_presence(section, 'tuitionAndFees', 'tuitionCharged')
    validate_presence(section, 'tuitionAndFees', 'mandatoryFees')

    validate_dollar_amount(section['tuitionCharged'], 'tuitionAndFees.tuitionCharged') if section['tuitionCharged'].present?
    validate_dollar_amount(section['mandatoryFees'],  'tuitionAndFees.mandatoryFees')  if section['mandatoryFees'].present?

    if section['hasWaivers'] == true && section['waiverAmount'].blank?
      errors.add(:form_data, 'tuitionAndFees.waiverAmount is required when hasWaivers is true')
    end

    if section['waiverAmount'].present?
      validate_dollar_amount(section['waiverAmount'], 'tuitionAndFees.waiverAmount')
    end
  end

  def validate_yellow_ribbon
    section = yellow_ribbon
    return unless section.is_a?(Hash)

    validate_presence(section, 'yellowRibbon', 'isUsingYellowRibbon')

    if section['isUsingYellowRibbon'] == true && section['institutionContribution'].blank?
      errors.add(:form_data, 'yellowRibbon.institutionContribution is required when isUsingYellowRibbon is true')
    end

    if section['institutionContribution'].present?
      validate_dollar_amount(section['institutionContribution'], 'yellowRibbon.institutionContribution')
    end
  end

  # ---------------------------------------------------------------------------
  # Primitive-level validators
  # ---------------------------------------------------------------------------

  def validate_presence(section, section_name, field_name)
    if section[field_name].nil? || (section[field_name].respond_to?(:empty?) && section[field_name].empty?)
      errors.add(:form_data, "#{section_name}.#{field_name} is required")
    end
  end

  def add_missing_section_error(section_name)
    errors.add(:form_data, "#{section_name} section is required and must be an object")
  end

  def validate_facility_code_format(value)
    return unless value.present?
    unless value.match?(/^\d{8}$/)
      errors.add(:form_data, 'Facility code must be exactly 8 digits')
    end
  end

  def validate_sco_name_format(value)
    return unless value.present?
    unless value.match?(/^[A-Za-z\s'\-]+$/)
      errors.add(:form_data, 'scoVerification.scoName contains invalid characters')
    end
    validate_string_length(value, 'scoVerification.scoName', 2, 100)
  end

  def validate_ssn_format(value)
    return unless value.present?
    unless value.match?(/^(?!000|666|9\d{2})\d{3}(?!00)\d{2}(?!0000)\d{4}$/)
      errors.add(:form_data, 'studentInformation.ssn is not a valid SSN format')
      return
    end
    # Additional rule: cannot be all the same digit (e.g., 111111111)
    if value.chars.uniq.length == 1
      errors.add(:form_data, 'studentInformation.ssn cannot be all the same digit')
    end
  end

  def validate_va_file_number_format(value)
    return unless value.present?
    unless value.match?(/^\d{7,9}$/)
      errors.add(:form_data, 'studentInformation.vaFileNumber must be 7 to 9 digits')
    end
  end

  def validate_date_format(value, field_path)
    return unless value.present?
    unless value.match?(/^\d{4}-\d{2}-\d{2}$/)
      errors.add(:form_data, "#{field_path} must be in YYYY-MM-DD format")
      return
    end
    begin
      Date.parse(value)
    rescue ArgumentError
      errors.add(:form_data, "#{field_path} is not a valid calendar date")
    end
  end

  def validate_date_of_birth(value)
    return unless value.present?
    begin
      dob = Date.parse(value)
    rescue ArgumentError, TypeError
      return # already reported by validate_date_format
    end
    if dob < Date.new(1900, 1, 1)
      errors.add(:form_data, 'studentInformation.dateOfBirth must be on or after 1900-01-01')
    end
    if dob > Date.today - 16.years
      errors.add(:form_data, 'studentInformation.dateOfBirth: student must be at least 16 years old')
    end
  end

  def validate_enrollment_dates(begin_date_str, end_date_str)
    return unless begin_date_str.present? && end_date_str.present?
    begin
      begin_date = Date.parse(begin_date_str)
      end_date   = Date.parse(end_date_str)
    rescue ArgumentError, TypeError
      return # already reported by format validator
    end

    if end_date <= begin_date
      errors.add(:form_data, 'enrollmentPeriod.enrollmentEndDate must be after enrollmentBeginDate')
    end

    # Advance certification limit: no more than 120 days in the future
    if begin_date > Date.today + 120.days
      errors.add(:form_data, 'enrollmentPeriod.enrollmentBeginDate cannot be more than 120 days in the future')
    end
  end

  def validate_credit_hour_count(value, field_path)
    return unless value.present?
    int_val = value.to_i
    if int_val < 0 || int_val > 99 || !value.is_a?(Integer) && value.to_s != int_val.to_s
      errors.add(:form_data, "#{field_path} must be an integer between 0 and 99")
    end
  end

  def validate_dollar_amount(value, field_path)
    return unless value.present?
    num = value.to_f
    if num < 0 || num > 999_999.99
      errors.add(:form_data, "#{field_path} must be a dollar amount between 0.00 and 999999.99")
    end
  end

  def validate_phone_format(value)
    return unless value.present?
    unless value.match?(/^\d{10}$/)
      errors.add(:form_data, 'certifyingOfficial.officialPhone must be exactly 10 digits with no separators')
    end
  end

  def validate_email_format(value)
    return unless value.present?
    unless value.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/) && value.length <= 256
      errors.add(:form_data, 'certifyingOfficial.officialEmail must be a valid email address (max 256 characters)')
    end
  end

  def validate_name_field(value, field_path)
    return unless value.present?
    unless value.match?(/^[A-Za-z\s'\-]+$/)
      errors.add(:form_data, "#{field_path} contains invalid characters (only letters, spaces, apostrophes, and hyphens allowed)")
    end
  end

  def validate_string_length(value, field_path, min_len, max_len)
    return unless value.present?
    if value.length < min_len
      errors.add(:form_data, "#{field_path} must be at least #{min_len} character(s)")
    elsif value.length > max_len
      errors.add(:form_data, "#{field_path} must be #{max_len} characters or fewer")
    end
  end

  def validate_address(address, prefix)
    return unless address.is_a?(Hash)
    %w[street city state postalCode].each do |field|
      if address[field].blank?
        errors.add(:form_data, "#{prefix}.#{field} is required")
      end
    end
    if address['postalCode'].present? && !address['postalCode'].match?(/^\d{5}(?:-\d{4})?$/)
      errors.add(:form_data, "#{prefix}.postalCode must be a valid ZIP code (XXXXX or XXXXX-XXXX)")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def form_data_section(key)
    return nil unless form_data.is_a?(Hash)
    form_data[key] || form_data[key.underscore]
  end
end