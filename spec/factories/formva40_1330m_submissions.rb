# frozen_string_literal: true

FactoryBot.define do
  factory :formva40_1330m_submission, class: 'Formva401330mSubmission' do
    user_uuid         { SecureRandom.uuid }
    submission_status { 'pending' }
    confirmation_number { nil }
    submitted_at       { nil }

    form_data do
      {
        'serviceStatusAtDeath'     => 'activeDuty',
        'submitterRole'            => 'nextOfKin',
        'certificationAttestation' => true,
        'applicant' => {
          'name'         => { 'first' => 'Jane', 'middle' => 'M', 'last' => 'Doe' },
          'daytimePhone' => '5551234567',
          'email'        => 'jane.doe@example.com',
          'address'      => {
            'street'     => '123 Main St',
            'city'       => 'Arlington',
            'state'      => 'VA',
            'postalCode' => '22201',
            'country'    => 'USA'
          }
        },
        'decedent' => {
          'name'        => { 'first' => 'John', 'last' => 'Doe' },
          'ssn'         => '123456789',
          'dateOfBirth' => '1985-06-15',
          'dateOfDeath' => '2024-01-10',
          'placeOfDeath' => {
            'city'    => 'Washington',
            'state'   => 'DC',
            'country' => 'USA'
          },
          'service' => {
            'branchOfService'  => 'army',
            'component'        => 'active',
            'rankAtDeath'      => 'Sergeant',
            'serviceEntryDate' => '2005-06-01',
            'serviceEndDate'   => '2024-01-10'
          }
        },
        'burialLocation' => {
          'cemeteryName'          => 'Arlington National Cemetery',
          'cemeteryContactName'   => 'Cemetery Contact',
          'cemeteryContactPhone'  => '7035551234',
          'existingMarkerPresent' => 'noExistingMarker',
          'cemeteryAddress'       => {
            'street'     => '1 Memorial Ave',
            'city'       => 'Arlington',
            'state'      => 'VA',
            'postalCode' => '22211',
            'country'    => 'USA'
          }
        },
        'markerRequest' => {
          'markerType' => 'uprightGranite'
        },
        'documents' => {
          'deathCertificate' => {
            'name'             => 'death_certificate.pdf',
            'size'             => 204_800,
            'confirmationCode' => 'abc-123-uuid',
            'attachmentId'     => 'L015'
          },
          'ddForm1300' => {
            'name'             => 'dd_form_1300.pdf',
            'size'             => 153_600,
            'confirmationCode' => 'def-456-uuid',
            'attachmentId'     => 'L023'
          }
        }
      }
    end

    trait :guard_reserve do
      form_data do
        {
          'serviceStatusAtDeath'             => 'guardOrReserve',
          'guardReserveQualifyingCircumstance' => 'diedOnActiveDutyForTraining',
          'submitterRole'                    => 'nextOfKin',
          'certificationAttestation'         => true,
          'applicant' => {
            'name'         => { 'first' => 'Jane', 'last' => 'Doe' },
            'daytimePhone' => '5551234567',
            'email'        => 'jane.doe@example.com',
            'address'      => {
              'street' => '123 Main St', 'city' => 'Arlington',
              'state' => 'VA', 'postalCode' => '22201', 'country' => 'USA'
            }
          },
          'decedent' => {
            'name'        => { 'first' => 'John', 'last' => 'Doe' },
            'ssn'         => '987654321',
            'dateOfBirth' => '1988-03-20',
            'dateOfDeath' => '2023-11-05',
            'placeOfDeath' => { 'city' => 'Fort Bragg', 'state' => 'NC', 'country' => 'USA' },
            'service' => {
              'branchOfService'  => 'armyNationalGuard',
              'component'        => 'guard',
              'rankAtDeath'      => 'Specialist',
              'serviceEntryDate' => '2008-07-01'
            }
          },
          'burialLocation' => {
            'cemeteryName'         => 'Pine Ridge Cemetery',
            'cemeteryContactName'  => 'Caretaker',
            'cemeteryContactPhone' => '9195551234',
            'existingMarkerPresent' => 'noExistingMarker',
            'cemeteryAddress'      => {
              'street' => '55 Pine Rd', 'city' => 'Raleigh',
              'state' => 'NC', 'postalCode' => '27601', 'country' => 'USA'
            }
          },
          'markerRequest' => { 'markerType' => 'flatBronze' },
          'documents' => {
            'deathCertificate' => { 'confirmationCode' => 'cert-uuid-gr' },
            'ngbForm22'        => { 'confirmationCode' => 'ngb22-uuid' }
          }
        }
      end
    end

    trait :submitted do
      submission_status { 'submitted' }
      confirmation_number { "NCA-#{SecureRandom.hex(5).upcase}" }
      submitted_at { Time.current }
    end

    trait :failed do
      submission_status { 'failed' }
    end
  end
end