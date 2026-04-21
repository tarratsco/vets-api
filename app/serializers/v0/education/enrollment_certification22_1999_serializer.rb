# app/serializers/v0/education/enrollment_certification22_1999_serializer.rb
# frozen_string_literal: true

require 'fast_jsonapi'

module V0
  module Education
    class EnrollmentCertification22_1999Serializer
      include FastJsonapi::ObjectSerializer

      set_type :enrollment_certification_22_1999
      set_id   :id

      attributes :form_id,
                 :status,
                 :confirmation_number,
                 :submitted_at,
                 :created_at,
                 :updated_at

      attribute :certification_type do |object|
        parsed = object.parsed_form
        parsed.dig('certificationTypeInfo', 'certificationType')
      end

      attribute :facility_code do |object|
        parsed = object.parsed_form
        parsed.dig('institutionInformation', 'facilityCode')
      end

      attribute :institution_name do |object|
        parsed = object.parsed_form
        parsed.dig('institutionInformation', 'institutionName')
      end

      attribute :student_name do |object|
        parsed    = object.parsed_form
        student   = parsed['studentIdentification'] || {}
        [
          student['studentFirstName'],
          student['studentMiddleName'],
          student['studentLastName']
        ].compact.join(' ')
      end

      attribute :chapter do |object|
        parsed = object.parsed_form
        parsed.dig('benefitChapter', 'chapter')
      end

      attribute :training_period do |object|
        parsed = object.parsed_form
        period = parsed['enrollmentPeriod'] || {}
        {
          begin_date: period['trainingPeriodBeginDate'],
          end_date:   period['trainingPeriodEndDate']
        }
      end
    end
  end
end