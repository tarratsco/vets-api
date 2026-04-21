# app/serializers/enrollment_certification_serializer.rb
# frozen_string_literal: true

class EnrollmentCertificationSerializer
  include JSONAPI::Serializer

  set_type :enrollment_certification

  set_id :id

  # Core status attributes returned immediately on create / show
  attributes :status, :confirmation_number, :submitted_at, :created_at, :updated_at

  # Subset of form data surfaced for the confirmation page and status polling
  attribute :form_id do |_object|
    EnrollmentCertification::FORM_ID
  end

  attribute :student_full_name do |object|
    object.student_full_name
  end

  attribute :facility_code do |object|
    object.facility_code
  end

  attribute :gi_chapter do |object|
    object.gi_chapter
  end

  attribute :enrollment_begin_date do |object|
    object.enrollment_period&.dig('enrollmentBeginDate')
  end

  attribute :enrollment_end_date do |object|
    object.enrollment_period&.dig('enrollmentEndDate')
  end

  attribute :certification_type do |object|
    object.certification_type_info&.dig('certificationType')
  end

  attribute :certifying_official_name do |object|
    object.certifying_official&.dig('officialName')
  end

  attribute :certifying_official_email do |object|
    object.certifying_official&.dig('officialEmail')
  end

  # Links for JSONAPI compliance
  link :self do |object|
    "/v0/education/enrollment_certifications/#{object.id}"
  end
end