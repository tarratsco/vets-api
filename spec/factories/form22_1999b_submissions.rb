# frozen_string_literal: true

FactoryBot.define do
  factory :form22_1999b_submission, class: 'Form22_1999bSubmission' do
    user_uuid     { SecureRandom.uuid }
    submitted_at  { nil }
    confirmation_number { nil }
    submission_error    { nil }

    form_data do
      {
        'institutionAndScoInformation' => {
          'facilityCode'    => '31000123',
          'institutionName' => 'State University of Example',
          'institutionAddress' => {
            'street' => '123 University Ave',
            'city'   => 'Richmond',
            'state'  => 'VA',
            'zip'    => '23220'
          },
          'scoFirstName' => 'Maria',
          'scoLastName'  => 'Hernandez',
          'scoTitle'     => 'Associate Registrar',
          'scoPhone'     => '5558675309',
          'scoEmail'     => 'certifying.official@university.edu'
        },
        'studentAndPriorCertification' => {
          'studentFirstName'          => 'James',
          'studentLastName'           => 'Nguyen',
          'ssnOrFileNumberIndicator'  => 'ssn',
          'studentSsn'                => '123456789',
          'benefitChapter'            => 'chapter_33',
          'originalCertBeginDate'     => '2024-08-19',
          'originalCertEndDate'       => '2024-12-15',
          'originalCreditHours'       => 12,
          'originalEnrollmentType'    => 'full_time'
        },
        'enrollmentChangeDetails' => {
          'typeOfChange'          => 'full_termination',
          'effectiveDateOfChange' => 10.days.ago.to_date.iso8601,
          'lastDateOfAttendance'  => 11.days.ago.to_date.iso8601,
          'reasonForChange'       => 'medical'
        },
        'scoCertificationAttested' => true
      }.to_json
    end

    trait :submitted do
      submitted_at        { Time.current }
      confirmation_number { SecureRandom.uuid }
    end

    trait :pending do
      submitted_at        { nil }
      confirmation_number { nil }
    end

    trait :correction do
      form_data do
        {
          'institutionAndScoInformation' => {
            'facilityCode'    => '31000123',
            'institutionName' => 'State University of Example',
            'institutionAddress' => {
              'street' => '123 University Ave',
              'city'   => 'Richmond',
              'state'  => 'VA',
              'zip'    => '23220'
            },
            'scoFirstName' => 'Maria',
            'scoLastName'  => 'Hernandez',
            'scoPhone'     => '5558675309',
            'scoEmail'     => 'certifying.official@university.edu'
          },
          'studentAndPriorCertification' => {
            'studentFirstName'          => 'James',
            'studentLastName'           => 'Nguyen',
            'ssnOrFileNumberIndicator'  => 'ssn',
            'studentSsn'                => '123456789',
            'benefitChapter'            => 'chapter_33',
            'originalCertBeginDate'     => '2024-08-19',
            'originalCertEndDate'       => '2024-12-15',
            'originalCreditHours'       => 12,
            'originalEnrollmentType'    => 'full_time'
          },
          'enrollmentChangeDetails' => {
            'typeOfChange'          => 'correction',
            'effectiveDateOfChange' => 10.days.ago.to_date.iso8601,
            'correctionDetails' => {
              'correctionItems'      => ['credit_hours'],
              'correctedCreditHours' => 9
            }
          },
          'scoCertificationAttested' => true
        }.to_json
      end
    end

    trait :with_mitigating_circumstances do
      form_data do
        {
          'institutionAndScoInformation' => {
            'facilityCode'    => '31000123',
            'institutionName' => 'State University of Example',
            'institutionAddress' => {
              'street' => '123 University Ave',
              'city'   => 'Richmond',
              'state'  => 'VA',
              'zip'    => '23220'
            },
            'scoFirstName' => 'Maria',
            'scoLastName'  => 'Hernandez',
            'scoPhone'     => '5558675309',
            'scoEmail'     => 'certifying.official@university.edu'
          },
          'studentAndPriorCertification' => {
            'studentFirstName'          => 'James',
            'studentLastName'           => 'Nguyen',
            'ssnOrFileNumberIndicator'  => 'ssn',
            'studentSsn'                => '123456789',
            'benefitChapter'            => 'chapter_33',
            'originalCertBeginDate'     => '2024-08-19',
            'originalCertEndDate'       => '2024-12-15',
            'originalCreditHours'       => 12,
            'originalEnrollmentType'    => 'full_time'
          },
          'enrollmentChangeDetails' => {
            'typeOfChange'          => 'full_termination',
            'effectiveDateOfChange' => 10.days.ago.to_date.iso8601,
            'lastDateOfAttendance'  => 11.days.ago.to_date.iso8601,
            'reasonForChange'       => 'medical',
            'mitigatingCircumstances' => {
              'mitigatingCircumstancesKnown'     => 'yes',
              'mitigatingCircumstancesNarrative' => 'Student was hospitalized for three weeks following surgery.'
            }
          },
          'scoCertificationAttested' => true
        }.to_json
      end
    end

    trait :late_submission do
      form_data do
        {
          'institutionAndScoInformation' => {
            'facilityCode'    => '31000123',
            'institutionName' => 'State University of Example',
            'institutionAddress' => {
              'street' => '123 University Ave',
              'city'   => 'Richmond',
              'state'  => 'VA',
              'zip'    => '23220'
            },
            'scoFirstName' => 'Maria',
            'scoLastName'  => 'Hernandez',
            'scoPhone'     => '5558675309',
            'scoEmail'     => 'certifying.official@university.edu'
          },
          'studentAndPriorCertification' => {
            'studentFirstName'          => 'James',
            'studentLastName'           => 'Nguyen',
            'ssnOrFileNumberIndicator'  => 'ssn',
            'studentSsn'                => '123456789',
            'benefitChapter'            => 'chapter_33',
            'originalCertBeginDate'     => '2024-06-01',
            'originalCertEndDate'       => '2024-12-15',
            'originalCreditHours'       => 12,
            'originalEnrollmentType'    => 'full_time'
          },
          'enrollmentChangeDetails' => {
            'typeOfChange'              => 'full_termination',
            'effectiveDateOfChange'     => 45.days.ago.to_date.iso8601,
            'lastDateOfAttendance'      => 46.days.ago.to_date.iso8601,
            'reasonForChange'           => 'voluntary_withdrawal',
            'lateSubmissionExplanation' => 'The institution experienced a system outage preventing earlier reporting.'
          },
          'scoCertificationAttested' => true
        }.to_json
      end
    end
  end
end