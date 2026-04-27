# frozen_string_literal: true

# Validates the JSON payload stored in Formva401330mSubmission#form_data.
# Business rules mirror the JSON Schema constraints and conditional logic
# documented in the architecture intent (§3.2).
class Formva401330mFormDataValidator < ActiveModel::Validator
  VALID_SERVICE_STATUSES = %w[activeDuty guardOrReserve].freeze
  VALID_SUBMITTER_ROLES  = %w[
    nextOfKin funeralHomeDirector cemeteryOfficial personalRepresentative
  ].freeze
  VALID_GUARD_CIRCUMSTANCES = %w[
    diedOnActiveDutyForTraining
    diedOnInactiveDutyForTraining
    entitledToRetiredPay
  ].freeze
  VALID_MARKER_TYPES = %w[
    uprightMarble uprightGranite flatGranite flatMarble flatBronze
  ].freeze
  SSN_PATTERN          = /\A\d{9}\z/
  PHONE_PATTERN        = /\A\d{10}\z/
  POSTAL_CODE_PATTERN  = /\A\d{5}(-\d{4})?\z/
  EMAIL_PATTERN        = URI::MailTo::EMAIL_REGEXP
  DATE_FORMAT          = '%Y-%m-%d'
  INSCRIPTION_MAX_LEN  = 60 # ⚠️ UNVERIFIED — confirm with NCA

  def validate(record)
    data = record.form_data
    return record.errors.add(:form_data, 'must be a Hash') unless data.is_a?(Hash)

    validate_service_status(record, data)
    validate_submitter_role(record, data)
    validate_certification(record, data)
    validate_applicant(record, data)
    validate_decedent(record, data)
    validate_burial_location(record, data)
    validate_marker_request(record, data)
    validate_documents(record, data)
  end

  private

  # ---------------------------------------------------------------------------
  def validate_service_status(record, data)
    status = data['serviceStatusAtDeath']
    unless VALID_SERVICE_STATUSES.include?(status)
      record.errors.add(:form_data, "serviceStatusAtDeath '#{status}' is not valid")
    end

    if status == 'guardOrReserve'
      circumstance = data['guardReserveQualifyingCircumstance']
      unless VALID_GUARD_CIRCUMSTANCES.include?(circumstance)
        record.errors.add(
          :form_data,
          "guardReserveQualifyingCircumstance '#{circumstance}' is not valid for Guard/Reserve submission"
        )
      end
    end
  end

  def validate_submitter_role(record, data)
    unless VALID_SUBMITTER_ROLES.include?(data['submitterRole'])
      record.errors.add(:form_data, "submitterRole '#{data['submitterRole']}' is not valid")
    end
  end

  def validate_certification(record, data)
    unless data['certificationAttestation'] == true
      record.errors.add(:form_data, 'certificationAttestation must be true')
    end
  end

  # ---------------------------------------------------------------------------
  def validate_applicant(record, data)
    applicant = data['applicant']
    unless applicant.is_a?(Hash)
      record.errors.add(:form_data, 'applicant is required')
      return
    end

    validate_full_name(record, applicant['name'], 'applicant.name')
    validate_phone(record, applicant['daytimePhone'], 'applicant.daytimePhone')
    validate_email_field(record, applicant['email'], 'applicant.email')
    validate_address(record, applicant['address'], 'applicant.address')

    role = data['submitterRole']
    if %w[funeralHomeDirector cemeteryOfficial].include?(role)
      if applicant['organizationName'].blank?
        record.errors.add(:form_data, 'applicant.organizationName is required for this submitter role')
      end
    end

    if role == 'personalRepresentative' && applicant['legalAuthorityDescription'].blank?
      record.errors.add(:form_data, 'applicant.legalAuthorityDescription is required for personalRepresentative')
    end
  end

  # ---------------------------------------------------------------------------
  def validate_decedent(record, data)
    decedent = data['decedent']
    unless decedent.is_a?(Hash)
      record.errors.add(:form_data, 'decedent is required')
      return
    end

    validate_full_name(record, decedent['name'], 'decedent.name')
    validate_ssn(record, decedent['ssn'])
    validate_date_field(record, decedent['dateOfBirth'], 'decedent.dateOfBirth')
    validate_date_field(record, decedent['dateOfDeath'], 'decedent.dateOfDeath')
    validate_dates_logical(record, decedent['dateOfBirth'], decedent['dateOfDeath'])
    validate_place_of_death(record, decedent['placeOfDeath'])
    validate_service(record, decedent['service'])
  end

  def validate_ssn(record, ssn)
    unless ssn.present? && ssn.match?(SSN_PATTERN)
      record.errors.add(:form_data, 'decedent.ssn must be exactly 9 digits')
    end
  end

  def validate_dates_logical(record, dob_str, dod_str)
    return unless dob_str.present? && dod_str.present?

    begin
      dob = Date.strptime(dob_str, DATE_FORMAT)
      dod = Date.strptime(dod_str, DATE_FORMAT)
      record.errors.add(:form_data, 'decedent.dateOfDeath must be after dateOfBirth') if dod <= dob
      record.errors.add(:form_data, 'decedent.dateOfDeath cannot be in the future')   if dod > Date.current
    rescue Date::Error
      # individual field date format errors already captured by validate_date_field
    end
  end

  def validate_place_of_death(record, place)
    unless place.is_a?(Hash)
      record.errors.add(:form_data, 'decedent.placeOfDeath is required')
      return
    end
    record.errors.add(:form_data, 'decedent.placeOfDeath.city is required')    if place['city'].blank?
    record.errors.add(:form_data, 'decedent.placeOfDeath.country is required') if place['country'].blank?
  end

  def validate_service(record, service)
    unless service.is_a?(Hash)
      record.errors.add(:form_data, 'decedent.service is required')
      return
    end
    record.errors.add(:form_data, 'decedent.service.branchOfService is required')  if service['branchOfService'].blank?
    record.errors.add(:form_data, 'decedent.service.component is required')        if service['component'].blank?
    record.errors.add(:form_data, 'decedent.service.rankAtDeath is required')      if service['rankAtDeath'].blank?
    validate_date_field(record, service['serviceEntryDate'], 'decedent.service.serviceEntryDate')
  end

  # ---------------------------------------------------------------------------
  def validate_burial_location(record, data)
    burial = data['burialLocation']
    unless burial.is_a?(Hash)
      record.errors.add(:form_data, 'burialLocation is required')
      return
    end

    record.errors.add(:form_data, 'burialLocation.cemeteryName is required')         if burial['cemeteryName'].blank?
    record.errors.add(:form_data, 'burialLocation.cemeteryContactName is required')  if burial['cemeteryContactName'].blank?
    validate_phone(record, burial['cemeteryContactPhone'], 'burialLocation.cemeteryContactPhone')
    validate_address(record, burial['cemeteryAddress'], 'burialLocation.cemeteryAddress')

    valid_markers = %w[noExistingMarker privateMarkerExists governmentMarkerAlreadyPlaced]
    unless valid_markers.include?(burial['existingMarkerPresent'])
      record.errors.add(:form_data, "burialLocation.existingMarkerPresent '#{burial['existingMarkerPresent']}' is not valid")
    end
  end

  # ---------------------------------------------------------------------------
  def validate_marker_request(record, data)
    marker = data['markerRequest']
    unless marker.is_a?(Hash)
      record.errors.add(:form_data, 'markerRequest is required')
      return
    end

    unless VALID_MARKER_TYPES.include?(marker['markerType'])
      record.errors.add(:form_data, "markerRequest.markerType '#{marker['markerType']}' is not valid")
    end

    inscription = marker['personalInscription']
    if inscription.present? && inscription.length > INSCRIPTION_MAX_LEN
      record.errors.add(
        :form_data,
        "markerRequest.personalInscription exceeds #{INSCRIPTION_MAX_LEN} characters"
      )
    end
  end

  # ---------------------------------------------------------------------------
  def validate_documents(record, data)
    docs = data['documents']
    unless docs.is_a?(Hash)
      record.errors.add(:form_data, 'documents is required')
      return
    end

    if docs.dig('deathCertificate', 'confirmationCode').blank?
      record.errors.add(:form_data, 'documents.deathCertificate is required')
    end

    case data['serviceStatusAtDeath']
    when 'activeDuty'
      if docs.dig('ddForm1300', 'confirmationCode').blank?
        record.errors.add(:form_data, 'documents.ddForm1300 is required for active duty submissions')
      end
    when 'guardOrReserve'
      if docs.dig('ngbForm22', 'confirmationCode').blank?
        record.errors.add(:form_data, 'documents.ngbForm22 is required for Guard/Reserve submissions')
      end
    end

    if data['submitterRole'] != 'nextOfKin' && docs.dig('authorizationDocument', 'confirmationCode').blank?
      record.errors.add(:form_data, 'documents.authorizationDocument is required for non-nextOfKin submissions')
    end

    additional = docs['additionalDocuments']
    if additional.present? && additional.length > 5
      record.errors.add(:form_data, 'documents.additionalDocuments cannot exceed 5 items')
    end
  end

  # ---------------------------------------------------------------------------
  # Shared field validators
  # ---------------------------------------------------------------------------
  def validate_full_name(record, name, path)
    unless name.is_a?(Hash)
      record.errors.add(:form_data, "#{path} is required")
      return
    end
    record.errors.add(:form_data, "#{path}.first is required") if name['first'].blank?
    record.errors.add(:form_data, "#{path}.last is required")  if name['last'].blank?
    if name['first'].present? && name['first'].length > 30
      record.errors.add(:form_data, "#{path}.first exceeds 30 characters")
    end
    if name['last'].present? && name['last'].length > 30
      record.errors.add(:form_data, "#{path}.last exceeds 30 characters")
    end
  end

  def validate_address(record, address, path)
    unless address.is_a?(Hash)
      record.errors.add(:form_data, "#{path} is required")
      return
    end
    record.errors.add(:form_data, "#{path}.street is required")     if address['street'].blank?
    record.errors.add(:form_data, "#{path}.city is required")       if address['city'].blank?
    record.errors.add(:form_data, "#{path}.state is required")      if address['state'].blank?
    record.errors.add(:form_data, "#{path}.postalCode is required") if address['postalCode'].blank?

    if address['postalCode'].present? && !address['postalCode'].match?(POSTAL_CODE_PATTERN)
      record.errors.add(:form_data, "#{path}.postalCode format is invalid")
    end
  end

  def validate_phone(record, phone, path)
    unless phone.present? && phone.match?(PHONE_PATTERN)
      record.errors.add(:form_data, "#{path} must be exactly 10 digits")
    end
  end

  def validate_email_field(record, email, path)
    unless email.present? && email.match?(EMAIL_PATTERN)
      record.errors.add(:form_data, "#{path} is not a valid email address")
    end
  end

  def validate_date_field(record, date_str, path)
    if date_str.blank?
      record.errors.add(:form_data, "#{path} is required")
      return
    end
    Date.strptime(date_str, DATE_FORMAT)
  rescue Date::Error
    record.errors.add(:form_data, "#{path} must be a valid date in YYYY-MM-DD format")
  end
end