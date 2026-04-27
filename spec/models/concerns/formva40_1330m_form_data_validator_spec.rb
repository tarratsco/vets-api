# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Formva401330mFormDataValidator do
  # Use the Formva401330mSubmission model as the host record
  def build_submission(overrides = {})
    base = {
      'serviceStatusAtDeath'     => 'activeDuty',
      'submitterRole'            => 'nextOfKin',
      'certificationAttestation' => true,
      'applicant' => {
        'name'         => { 'first' => 'Jane', 'last' => 'Smith' },
        'daytimePhone' => '5551234567',
        'email'        => 'j@example.com',
        'address'      => {
          'street'     => '1 A St',
          'city'       => 'City',
          'state'      => 'VA',
          'postalCode' => '20001',
          'country'    => 'USA'
        }
      },
      'decedent' => {
        'name'        => { 'first' => 'Mark', 'last' => 'Smith' },
        'ssn'         => '111223333',
        'dateOfBirth' => '1990-01-01',
        'dateOfDeath' => '2024-06-15',
        'placeOfDeath' => { 'city' => 'DC', 'country' => 'USA' },
        'service'      => {
          'branchOfService'  => 'navy',
          'component'        => 'active',
          'rankAtDeath'      => 'Petty Officer',
          'serviceEntryDate' => '2010-05-01'
        }
      },
      'burialLocation' => {
        'cemeteryName'         => 'Cemetery',
        'cemeteryContactName'  => 'Director',
        'cemeteryContactPhone' => '8005551234',
        'existingMarkerPresent' => 'noExistingMarker',
        'cemeteryAddress'      => {
          'street'     => '1 Cem Rd',
          'city'       => 'City',
          'state'      => 'VA',
          'postalCode' => '20002',
          'country'    => 'USA'
        }
      },
      'markerRequest' => { 'markerType' => 'flatMarble' },
      'documents'     => {
        'deathCertificate' => { 'confirmationCode' => 'uuid-cert' },
        'ddForm1300'       => { 'confirmationCode' => 'uuid-dd1300' }
      }
    }
    Formva401330mSubmission.new(
      user_uuid:  SecureRandom.uuid,
      form_data:  base.deep_merge(overrides)
    )
  end

  describe 'serviceStatusAtDeath' do
    it 'is valid with "activeDuty"' do
      expect(build_submission).to be_valid
    end

    it 'is valid with "guardOrReserve" and required circumstance' do
      sub = build_submission(
        'serviceStatusAtDeath'             => 'guardOrReserve',
        'guardReserveQualifyingCircumstance' => 'entitledToRetiredPay',
        'documents' => {
          'deathCertificate' => { 'confirmationCode' => 'c1' },
          'ngbForm22'        => { 'confirmationCode' => 'c2' }
        }
      )
      expect(sub).to be_valid
    end

    it 'is invalid with an unrecognised service status' do
      sub = build_submission('serviceStatusAtDeath' => 'dischargedVeteran')
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/serviceStatusAtDeath/i)
    end
  end

  describe 'decedent SSN' do
    it 'is invalid with fewer than 9 digits' do
      sub = build_submission('decedent' => { 'ssn' => '12345' })
      expect(sub).not_to be_valid
    end

    it 'is invalid with letters in SSN' do
      sub = build_submission('decedent' => { 'ssn' => 'abcdefghi' })
      expect(sub).not_to be_valid
    end
  end

  describe 'applicant email' do
    it 'is invalid with a malformed email' do
      sub = build_submission('applicant' => { 'email' => 'not-an-email' })
      expect(sub).not_to be_valid
    end
  end

  describe 'personalInscription length' do
    it 'is valid with exactly 60 characters' do
      sub = build_submission(
        'markerRequest' => {
          'markerType'          => 'flatMarble',
          'personalInscription' => 'A' * 60
        }
      )
      expect(sub).to be_valid
    end

    it 'is invalid with 61 characters' do
      sub = build_submission(
        'markerRequest' => {
          'markerType'          => 'flatMarble',
          'personalInscription' => 'A' * 61
        }
      )
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/inscription/i)
    end
  end

  describe 'additionalDocuments maxItems' do
    it 'is invalid with more than 5 additional documents' do
      extra_docs = Array.new(6) { { 'confirmationCode' => SecureRandom.uuid } }
      sub = build_submission('documents' => { 'additionalDocuments' => extra_docs })
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/additionalDocuments/i)
    end
  end

  describe 'submitter role — organizationName requirement' do
    it 'is invalid for funeralHomeDirector without organizationName' do
      sub = build_submission(
        'submitterRole' => 'funeralHomeDirector',
        'documents' => {
          'deathCertificate'    => { 'confirmationCode' => 'c1' },
          'ddForm1300'          => { 'confirmationCode' => 'c2' },
          'authorizationDocument' => { 'confirmationCode' => 'c3' }
        }
      )
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/organizationName/i)
    end
  end
end