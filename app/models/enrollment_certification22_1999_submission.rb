# app/models/enrollment_certification22_1999_submission.rb
# frozen_string_literal: true

class EnrollmentCertification22_1999Submission < ApplicationRecord
  self.table_name = 'enrollment_certification22_1999_submissions'

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  STATUSES = %w[pending submitted failed].freeze

  VALID_CERTIFICATION_TYPES   = %w[original amended termination].freeze
  VALID_CHAPTERS              = %w[chapter33 chapter30 chapter1606 chapter35 chapter32].freeze
  VALID_INSTITUTION_TYPES     = %w[public privateNonProfit proprietary].freeze
  VALID_DEGREE_LEVELS         = %w[
    nonCollegeDegree associate bachelors masters doctoral certificate vocationalTechnical
  ].freeze
  VALID_STANDARD_LENGTHS      = %w[1semester 1year 2years 3years 4years other].freeze
  VALID_CREDIT_TYPES          = %w[creditHours clockHours].freeze
  VALID_TRAINING_TIMES        = %w[fullTime threeQuarterTime halfTime lessThanHalfTime].freeze
  VALID_IDENTIFIER_TYPES      = %w[ssn vaFileNumber].freeze
  VALID_TERMINATION_REASONS   = %w[
    studentWithdrew studentExpelled didNotReturnFromBreak changeInTrainingTime
    unsatisfactoryProgress graduatedEarly militaryDeployment other
  ].freeze

  STATE_CODES = %w[
    AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI
    MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT
    VA WA WV WI WY AS GU MP PR VI FM MH PW
  ].freeze

  STUDENT_SUFFIXES = ['Jr.', 'Sr.', 'II', 'III', 'IV'].freeze

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :pending,   -> { where(status: 'pending') }
  scope :submitted, -> { where(status: 'submitted') }
  scope :failed,    -> { where(status: 'failed') }
  scope :for_user,  ->(uuid) { where(user_uuid: uuid) }
  scope :recent,    -> { order(created_at: :desc) }

  # ---------------------------------------------------------------------------
  # Validations — top-level required fields (presence)
  # ---------------------------------------------------------------------------

  validates :user_uuid,  presence: true
  validates :form_id,    presence: true
  validates :form_data,  presence: true
  validates :status,     presence: true, inclusion: { in: STATUSES }

  # Validate the JSON blob fields via parsed helper
  validate :validate_sco_authorization
  validate :validate_certification_type_info
  validate :validate_institution_information
  validate :validate_student_identification
  validate :validate_benefit_chapter
  validate :validate_enrollment_period
  validate :validate_program_information
  validate :validate_credit_hours_training_time
  validate :validate_sco_certification
  validate :validate_conditional_sections

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  before_validation :set_default_status

  # ---------------------------------------------------------------------------
  # Public interface
  # ---------------------------------------------------------------------------

  def parsed_form
    @parsed_form ||= form_data.is_a?(String) ? JSON.parse(form_data) : form_data
  rescue JSON::ParserError
    {}
  end

  def certification_type
    dig_form('certificationTypeInfo', 'certificationType')
  end

  def chapter
    dig_form('benefitChapter', 'chapter')
  end

  def yellow_ribbon_participant?
    dig_form('institutionInformation', 'yellowRibbonParticipant') == true
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  private

  def set_default_status
    self.status ||= 'pending'
  end

  def dig_form(*keys)
    parsed_form.dig(*keys)
  end

  # ----- scoAuthorization -----------------------------------------------------

  def validate_sco_authorization
    sco_auth = dig_form('scoAuthorization')

    if sco_auth.blank?
      errors.add(:form_data, 'scoAuthorization is required')
      return
    end

    unless sco_auth['scoAttestation'] == true
      errors.add(:form_data, 'scoAttestation must be accepted (true) to proceed')
    end

    user_id = sco_auth['scoUserId']
    if user_id.present? && (user_id.length < 1 || user_id.length > 50)
      errors.add(:form_data, 'scoUserId must be between 1 and 50 characters')
    end
  end

  # ----- certificationTypeInfo -------------------------------------------------

  def validate_certification_type_info
    cert_type_info = dig_form('certificationTypeInfo')

    if cert_type_info.blank?
      errors.add(:form_data, 'certificationTypeInfo is required')
      return
    end

    cert_type = cert_type_info['certificationType']
    if cert_type.blank?
      errors.add(:form_data, 'certificationType is required')
    elsif VALID_CERTIFICATION_TYPES.exclude?(cert_type)
      errors.add(:form_data, "certificationType must be one of: #{VALID_CERTIFICATION_TYPES.join(', ')}")
    end
  end

  # ----- institutionInformation ------------------------------------------------

  def validate_institution_information
    inst = dig_form('institutionInformation')

    if inst.blank?
      errors.add(:form_data, 'institutionInformation is required')
      return
    end

    validate_presence(inst, 'facilityCode',          'institutionInformation.facilityCode')
    validate_presence(inst, 'institutionName',        'institutionInformation.institutionName')
    validate_presence(inst, 'addressLine1',           'institutionInformation.addressLine1')
    validate_presence(inst, 'city',                   'institutionInformation.city')
    validate_presence(inst, 'state',                  'institutionInformation.state')
    validate_presence(inst, 'zipCode',                'institutionInformation.zipCode')
    validate_presence(inst, 'institutionType',        'institutionInformation.institutionType')

    facility_code = inst['facilityCode']
    if facility_code.present? && facility_code !~ /^\d{8}$/
      errors.add(:form_data, 'facilityCode must be exactly 8 numeric digits')
    end

    inst_name = inst['institutionName']
    if inst_name.present? && inst_name.length > 200
      errors.add(:form_data, 'institutionName must not exceed 200 characters')
    end

    addr1 = inst['addressLine1']
    if addr1.present? && addr1.length > 100
      errors.add(:form_data, 'addressLine1 must not exceed 100 characters')
    end

    addr2 = inst['addressLine2']
    if addr2.present? && addr2.length > 100
      errors.add(:form_data, 'addressLine2 must not exceed 100 characters')
    end

    city = inst['city']
    if city.present? && city.length > 100
      errors.add(:form_data, 'city must not exceed 100 characters')
    end

    state = inst['state']
    if state.present? && STATE_CODES.exclude?(state)
      errors.add(:form_data, "state must be a valid US state or territory abbreviation")
    end

    zip = inst['zipCode']
    if zip.present? && zip !~ /^\d{5}(-\d{4})?$/
      errors.add(:form_data, 'zipCode must be a valid 5-digit or ZIP+4 format')
    end

    inst_type = inst['institutionType']
    if inst_type.present? && VALID_INSTITUTION_TYPES.exclude?(inst_type)
      errors.add(:form_data, "institutionType must be one of: #{VALID_INSTITUTION_TYPES.join(', ')}")
    end

    yr = inst['yellowRibbonParticipant']
    unless [true, false].include?(yr)
      errors.add(:form_data, 'yellowRibbonParticipant must be a boolean value')
    end
  end

  # ----- studentIdentification -------------------------------------------------

  def validate_student_identification
    student = dig_form('studentIdentification')

    if student.blank?
      errors.add(:form_data, 'studentIdentification is required')
      return
    end

    validate_presence(student, 'identifierType',      'studentIdentification.identifierType')
    validate_presence(student, 'studentIdentifier',   'studentIdentification.studentIdentifier')
    validate_presence(student, 'studentFirstName',    'studentIdentification.studentFirstName')
    validate_presence(student, 'studentLastName',     'studentIdentification.studentLastName')
    validate_presence(student, 'studentDateOfBirth',  'studentIdentification.studentDateOfBirth')

    id_type = student['identifierType']
    if id_type.present? && VALID_IDENTIFIER_TYPES.exclude?(id_type)
      errors.add(:form_data, "identifierType must be one of: #{VALID_IDENTIFIER_TYPES.join(', ')}")
    end

    if id_type == 'ssn'
      ssn = student['studentSsn']
      if ssn.blank?
        errors.add(:form_data, 'studentSsn is required when identifierType is ssn')
      elsif ssn !~ /^\d{9}$/
        errors.add(:form_data, 'studentSsn must be exactly 9 numeric digits')
      end
    elsif id_type == 'vaFileNumber'
      va_file = student['studentVaFileNumber']
      if va_file.blank?
        errors.add(:form_data, 'studentVaFileNumber is required when identifierType is vaFileNumber')
      elsif va_file !~ /^[a-zA-Z0-9]{5,10}$/
        errors.add(:form_data, 'studentVaFileNumber must be 5-10 alphanumeric characters')
      end
    end

    first_name = student['studentFirstName']
    if first_name.present? && first_name.length > 50
      errors.add(:form_data, 'studentFirstName must not exceed 50 characters')
    end

    middle_name = student['studentMiddleName']
    if middle_name.present? && middle_name.length > 50
      errors.add(:form_data, 'studentMiddleName must not exceed 50 characters')
    end

    last_name = student['studentLastName']
    if last_name.present? && last_name.length > 50
      errors.add(:form_data, 'studentLastName must not exceed 50 characters')
    end

    suffix = student['studentSuffix']
    if suffix.present? && STUDENT_SUFFIXES.exclude?(suffix)
      errors.add(:form_data, "studentSuffix must be one of: #{STUDENT_SUFFIXES.join(', ')}")
    end

    dob = student['studentDateOfBirth']
    validate_date_format(dob, 'studentDateOfBirth') if dob.present?

    email = student['studentEmailAddress']
    if email.present?
      if email.length > 256
        errors.add(:form_data, 'studentEmailAddress must not exceed 256 characters')
      elsif email !~ URI::MailTo::EMAIL_REGEXP
        errors.add(:form_data, 'studentEmailAddress must be a valid email format')
      end
    end
  end

  # ----- benefitChapter --------------------------------------------------------

  def validate_benefit_chapter
    benefit = dig_form('benefitChapter')

    if benefit.blank?
      errors.add(:form_data, 'benefitChapter is required')
      return
    end

    ch = benefit['chapter']
    if ch.blank?
      errors.add(:form_data, 'benefitChapter.chapter is required')
    elsif VALID_CHAPTERS.exclude?(ch)
      errors.add(:form_data, "benefitChapter.chapter must be one of: #{VALID_CHAPTERS.join(', ')}")
    end

    # activeDutyStatus is conditionally meaningful for chapter33
    ads = benefit['activeDutyStatus']
    if ads.present? && ![true, false].include?(ads)
      errors.add(:form_data, 'activeDutyStatus must be a boolean value')
    end
  end

  # ----- enrollmentPeriod ------------------------------------------------------

  def validate_enrollment_period
    period = dig_form('enrollmentPeriod')

    if period.blank?
      errors.add(:form_data, 'enrollmentPeriod is required')
      return
    end

    begin_date = period['trainingPeriodBeginDate']
    end_date   = period['trainingPeriodEndDate']

    validate_presence(period, 'trainingPeriodBeginDate', 'enrollmentPeriod.trainingPeriodBeginDate')
    validate_presence(period, 'trainingPeriodEndDate',   'enrollmentPeriod.trainingPeriodEndDate')

    if begin_date.present? && end_date.present?
      validate_date_format(begin_date, 'trainingPeriodBeginDate')
      validate_date_format(end_date,   'trainingPeriodEndDate')

      begin
        bd = Date.parse(begin_date)
        ed = Date.parse(end_date)
        today = Date.current

        if ed < bd
          errors.add(:form_data, 'trainingPeriodEndDate must be on or after trainingPeriodBeginDate')
        end

        # Advance certification: begin date must not be more than 120 days in the future
        if bd > today + 120
          errors.add(:form_data, 'trainingPeriodBeginDate cannot be more than 120 days in the future')
        end

        # Retroactive certification: begin date must not be more than 1 year in the past
        if bd < today - 365
          errors.add(:form_data, 'trainingPeriodBeginDate cannot be more than 1 year in the past')
        end
      rescue ArgumentError
        # Individual date format errors already added above; skip cross-validation
      end
    end

    ref_num = period['priorCertificationReferenceNumber']
    if ref_num.present? && ref_num.length > 50
      errors.add(:form_data, 'priorCertificationReferenceNumber must not exceed 50 characters')
    end

    eff_date = period['effectiveDateOfChange']
    validate_date_format(eff_date, 'effectiveDateOfChange') if eff_date.present?
  end

  # ----- programInformation ----------------------------------------------------

  def validate_program_information
    prog = dig_form('programInformation')

    if prog.blank?
      errors.add(:form_data, 'programInformation is required')
      return
    end

    validate_presence(prog, 'programMajorName',         'programInformation.programMajorName')
    validate_presence(prog, 'degreeCertificateLevel',   'programInformation.degreeCertificateLevel')
    validate_presence(prog, 'standardLengthOfProgram',  'programInformation.standardLengthOfProgram')

    major = prog['programMajorName']
    if major.present? && major.length > 200
      errors.add(:form_data, 'programMajorName must not exceed 200 characters')
    end

    degree = prog['degreeCertificateLevel']
    if degree.present? && VALID_DEGREE_LEVELS.exclude?(degree)
      errors.add(:form_data, "degreeCertificateLevel must be one of: #{VALID_DEGREE_LEVELS.join(', ')}")
    end

    std_length = prog['standardLengthOfProgram']
    if std_length.present? && VALID_STANDARD_LENGTHS.exclude?(std_length)
      errors.add(:form_data, "standardLengthOfProgram must be one of: #{VALID_STANDARD_LENGTHS.join(', ')}")
    end

    if std_length == 'other'
      std_other = prog['standardLengthOther']
      if std_other.blank?
        errors.add(:form_data, 'standardLengthOther is required when standardLengthOfProgram is "other"')
      elsif std_other.length > 100
        errors.add(:form_data, 'standardLengthOther must not exceed 100 characters')
      end
    end
  end

  # ----- creditHoursTrainingTime -----------------------------------------------

  def validate_credit_hours_training_time
    credit = dig_form('creditHoursTrainingTime')

    if credit.blank?
      errors.add(:form_data, 'creditHoursTrainingTime is required')
      return
    end

    validate_presence(credit, 'creditType',                'creditHoursTrainingTime.creditType')
    validate_presence(credit, 'hoursEnrolled',             'creditHoursTrainingTime.hoursEnrolled')
    validate_presence(credit, 'fullTimeStandard',          'creditHoursTrainingTime.fullTimeStandard')
    validate_presence(credit, 'trainingTimeClassification','creditHoursTrainingTime.trainingTimeClassification')

    credit_type = credit['creditType']
    if credit_type.present? && VALID_CREDIT_TYPES.exclude?(credit_type)
      errors.add(:form_data, "creditType must be one of: #{VALID_CREDIT_TYPES.join(', ')}")
    end

    hours_enrolled = credit['hoursEnrolled']
    if hours_enrolled.present?
      unless hours_enrolled.is_a?(Integer) && hours_enrolled >= 0 && hours_enrolled <= 30
        errors.add(:form_data, 'hoursEnrolled must be an integer between 0 and 30')
      end
    end

    full_time_std = credit['fullTimeStandard']
    if full_time_std.present?
      unless full_time_std.is_a?(Integer) && full_time_std >= 1 && full_time_std <= 30
        errors.add(:form_data, 'fullTimeStandard must be an integer between 1 and 30')
      end
    end

    training_class = credit['trainingTimeClassification']
    if training_class.present? && VALID_TRAINING_TIMES.exclude?(training_class)
      errors.add(:form_data, "trainingTimeClassification must be one of: #{VALID_TRAINING_TIMES.join(', ')}")
    end

    rate = credit['rateOfPursuit']
    if rate.present?
      unless rate.is_a?(Integer) && rate >= 0 && rate <= 100
        errors.add(:form_data, 'rateOfPursuit must be an integer between 0 and 100')
      end

      # Server-side recalculation verification
      if hours_enrolled.is_a?(Integer) && full_time_std.is_a?(Integer) && full_time_std > 0
        expected_rate = (hours_enrolled.to_f / full_time_std * 100).round
        unless rate == expected_rate
          errors.add(:form_data, "rateOfPursuit value #{rate} does not match calculated value #{expected_rate}")
        end
      end
    end
  end

  # ----- scoCertification ------------------------------------------------------

  def validate_sco_certification
    cert = dig_form('scoCertification')

    if cert.blank?
      errors.add(:form_data, 'scoCertification is required')
      return
    end

    validate_presence(cert, 'scoFirstName',            'scoCertification.scoFirstName')
    validate_presence(cert, 'scoLastName',             'scoCertification.scoLastName')
    validate_presence(cert, 'scoTitle',                'scoCertification.scoTitle')
    validate_presence(cert, 'scoPhoneNumber',          'scoCertification.scoPhoneNumber')
    validate_presence(cert, 'scoEmailAddress',         'scoCertification.scoEmailAddress')
    validate_presence(cert, 'dateOfCertification',     'scoCertification.dateOfCertification')

    unless cert['certificationAttestation'] == true
      errors.add(:form_data, 'certificationAttestation must be accepted (true) to submit')
    end

    phone = cert['scoPhoneNumber']
    if phone.present? && phone !~ /^\d{10}$/
      errors.add(:form_data, 'scoPhoneNumber must be exactly 10 numeric digits')
    end

    fax = cert['scoFaxNumber']
    if fax.present? && fax !~ /^\d{10}$/
      errors.add(:form_data, 'scoFaxNumber must be exactly 10 numeric digits')
    end

    email = cert['scoEmailAddress']
    if email.present?
      if email.length > 256
        errors.add(:form_data, 'scoEmailAddress must not exceed 256 characters')
      elsif email !~ URI::MailTo::EMAIL_REGEXP
        errors.add(:form_data, 'scoEmailAddress must be a valid email format')
      end
    end

    first_name = cert['scoFirstName']
    if first_name.present? && first_name.length > 50
      errors.add(:form_data, 'scoFirstName must not exceed 50 characters')
    end

    last_name = cert['scoLastName']
    if last_name.present? && last_name.length > 50
      errors.add(:form_data, 'scoLastName must not exceed 50 characters')
    end

    title = cert['scoTitle']
    if title.present? && title.length > 100
      errors.add(:form_data, 'scoTitle must not exceed 100 characters')
    end

    cert_date = cert['dateOfCertification']
    validate_date_format(cert_date, 'dateOfCertification') if cert_date.present?
  end

  # ----- Conditional section validations ---------------------------------------

  def validate_conditional_sections
    validate_tuition_fees_section
    validate_yellow_ribbon_section
    validate_prior_certification_changes_section
    validate_termination_information_section
  end

  def validate_tuition_fees_section
    # Phase 1: Chapter 33 only — tuition fees are required
    return unless chapter == 'chapter33'

    fees = dig_form('tuitionFees')
    if fees.blank?
      errors.add(:form_data, 'tuitionFees is required for Chapter 33 certifications')
      return
    end

    validate_presence(fees, 'tuitionCharged',        'tuitionFees.tuitionCharged')
    validate_presence(fees, 'mandatoryFeesCharged',  'tuitionFees.mandatoryFeesCharged')

    yr = fees['nonResidentStudent']
    unless [true, false].include?(yr)
      errors.add(:form_data, 'tuitionFees.nonResidentStudent must be a boolean value')
    end

    tuition = fees['tuitionCharged']
    if tuition.present? && (!tuition.is_a?(Numeric) || tuition < 0)
      errors.add(:form_data, 'tuitionFees.tuitionCharged must be a non-negative number')
    end

    mandatory = fees['mandatoryFeesCharged']
    if mandatory.present? && (!mandatory.is_a?(Numeric) || mandatory < 0)
      errors.add(:form_data, 'tuitionFees.mandatoryFeesCharged must be a non-negative number')
    end

    # Require itemized description if mandatory fees > 0
    if mandatory.is_a?(Numeric) && mandatory > 0
      itemized = fees['itemizedFeeDescription']
      if itemized.blank?
        errors.add(:form_data, 'tuitionFees.itemizedFeeDescription is required when mandatoryFeesCharged > 0')
      elsif itemized.length > 2000
        errors.add(:form_data, 'tuitionFees.itemizedFeeDescription must not exceed 2000 characters')
      end
    end

    total = fees['totalTuitionAndFees']
    if total.present? && tuition.is_a?(Numeric) && mandatory.is_a?(Numeric)
      expected_total = tuition + mandatory
      unless (total - expected_total).abs < 0.01
        errors.add(:form_data, "tuitionFees.totalTuitionAndFees #{total} does not match calculated value #{expected_total}")
      end
    end
  end

  def validate_yellow_ribbon_section
    return unless chapter == 'chapter33' && yellow_ribbon_participant?

    yr = dig_form('yellowRibbon')
    if yr.blank?
      errors.add(:form_data, 'yellowRibbon is required for Chapter 33 Yellow Ribbon participants')
      return
    end

    contribution = yr['schoolYellowRibbonContribution']
    if contribution.blank?
      errors.add(:form_data, 'yellowRibbon.schoolYellowRibbonContribution is required')
    elsif !contribution.is_a?(Numeric) || contribution < 0
      errors.add(:form_data, 'yellowRibbon.schoolYellowRibbonContribution must be a non-negative number')
    end

    ref_num = yr['yellowRibbonAgreementReferenceNumber']
    if ref_num.present? && ref_num.length > 50
      errors.add(:form_data, 'yellowRibbon.yellowRibbonAgreementReferenceNumber must not exceed 50 characters')
    end
  end

  def validate_prior_certification_changes_section
    return unless certification_type == 'amended'

    changes = dig_form('priorCertificationChanges')
    if changes.blank?
      errors.add(:form_data, 'priorCertificationChanges is required for amended certifications')
      return
    end

    change_desc = changes['changeDescription']
    if change_desc.blank?
      errors.add(:form_data, 'priorCertificationChanges.changeDescription is required')
    elsif change_desc.length > 2000
      errors.add(:form_data, 'priorCertificationChanges.changeDescription must not exceed 2000 characters')
    end

    types = changes['typesOfChange'] || {}
    added   = types['addedCourses']
    dropped = types['droppedCourses']

    if added == true || dropped == true
      course_date = changes['courseChangeDate']
      if course_date.blank?
        errors.add(:form_data, 'priorCertificationChanges.courseChangeDate is required when courses were added or dropped')
      else
        validate_date_format(course_date, 'courseChangeDate')
      end
    end

    if changes['mitigatingCircumstancesApply'] == true
      mitigation_desc = changes['mitigatingCircumstancesDescription']
      if mitigation_desc.blank?
        errors.add(:form_data, 'priorCertificationChanges.mitigatingCircumstancesDescription is required when mitigatingCircumstancesApply is true')
      elsif mitigation_desc.length > 2000
        errors.add(:form_data, 'priorCertificationChanges.mitigatingCircumstancesDescription must not exceed 2000 characters')
      end
    end

    updated_hours = changes['updatedHoursEnrolled']
    if updated_hours.present? && (!updated_hours.is_a?(Integer) || updated_hours < 0 || updated_hours > 30)
      errors.add(:form_data, 'priorCertificationChanges.updatedHoursEnrolled must be an integer between 0 and 30')
    end

    updated_class = changes['updatedTrainingTimeClassification']
    if updated_class.present? && VALID_TRAINING_TIMES.exclude?(updated_class)
      errors.add(:form_data, "priorCertificationChanges.updatedTrainingTimeClassification must be one of: #{VALID_TRAINING_TIMES.join(', ')}")
    end
  end

  def validate_termination_information_section
    return unless certification_type == 'termination'

    term = dig_form('terminationInformation')
    if term.blank?
      errors.add(:form_data, 'terminationInformation is required for termination certifications')
      return
    end

    validate_presence(term, 'terminationReason',       'terminationInformation.terminationReason')
    validate_presence(term, 'lastDateOfAttendance',    'terminationInformation.lastDateOfAttendance')

    npg = term['nonPunitiveGradesReceived']
    unless [true, false].include?(npg)
      errors.add(:form_data, 'terminationInformation.nonPunitiveGradesReceived must be a boolean value')
    end

    mitigation = term['mitigatingCircumstancesApply']
    unless [true, false].include?(mitigation)
      errors.add(:form_data, 'terminationInformation.mitigatingCircumstancesApply must be a boolean value')
    end

    reason = term['terminationReason']
    if reason.present? && VALID_TERMINATION_REASONS.exclude?(reason)
      errors.add(:form_data, "terminationInformation.terminationReason must be one of: #{VALID_TERMINATION_REASONS.join(', ')}")
    end

    lda = term['lastDateOfAttendance']
    validate_date_format(lda, 'lastDateOfAttendance') if lda.present?

    wd = term['officialWithdrawalDate']
    validate_date_format(wd, 'officialWithdrawalDate') if wd.present?

    if term['mitigatingCircumstancesApply'] == true
      mitigation_desc = term['mitigatingCircumstancesDescription']
      if mitigation_desc.blank?
        errors.add(:form_data, 'terminationInformation.mitigatingCircumstancesDescription is required when mitigatingCircumstancesApply is true')
      elsif mitigation_desc.length > 2000
        errors.add(:form_data, 'terminationInformation.mitigatingCircumstancesDescription must not exceed 2000 characters')
      end
    end
  end

  # ----- Helper validations ----------------------------------------------------

  def validate_presence(hash, key, label)
    errors.add(:form_data, "#{label} is required") if hash[key].blank?
  end

  def validate_date_format(date_string, field_name)
    Date.parse(date_string)
  rescue ArgumentError, TypeError
    errors.add(:form_data, "#{field_name} must be a valid date in YYYY-MM-DD format")
  end
end