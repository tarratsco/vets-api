# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Formva401330mSubmission, type: :model do
  # ---------------------------------------------------------------------------
  # FactoryBot factory — defined in spec/factories/formva40_1330m_submissions.rb
  # ---------------------------------------------------------------------------
  subject(:submission) { build(:formva40_1330m_submission) }

  # ---------------------------------------------------------------------------
  # Basic validity
  # ---------------------------------------------------------------------------
  it 'is valid with factory defaults' do
    expect(submission).to be_valid
  end

  # ---------------------------------------------------------------------------
  # Presence validations
  # ---------------------------------------------------------------------------
  it 'is invalid without form_data' do
    submission.form_data = nil
    expect(submission).not_to be_valid
    expect(submission.errors[:form_data]).not_to be_empty
  end

  it 'is invalid without user_uuid' do
    submission.user_uuid = nil
    expect(submission).not_to be_valid
    expect(submission.errors[:user_uuid]).not_to be_empty
  end

  # ---------------------------------------------------------------------------
  # submission_status inclusion validation
  # ---------------------------------------------------------------------------
  it 'is valid with status "pending"' do
    submission.submission_status = 'pending'
    expect(submission).to be_valid
  end

  it 'is valid with status "submitted"' do
    submission.submission_status = 'submitted'
    expect(submission).to be_valid
  end

  it 'is valid with status "failed"' do
    submission.submission_status = 'failed'
    expect(submission).to be_valid
  end

  it 'is invalid with an unrecognised status' do
    submission.submission_status = 'banana'
    expect(submission).not_to be_valid
    expect(submission.errors[:submission_status]).not_to be_empty
  end

  # ---------------------------------------------------------------------------
  # Default status callback
  # ---------------------------------------------------------------------------
  it 'defaults submission_status to "pending" on create' do
    submission.submission_status = nil
    submission.valid?
    expect(submission.submission_status).to eq('pending')
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  describe '.pending scope' do
    it 'returns only pending submissions' do
      pending_sub   = create(:formva40_1330m_submission, submission_status: 'pending')
      submitted_sub = create(:formva40_1330m_submission, submission_status: 'submitted')

      expect(described_class.pending).to include(pending_sub)
      expect(described_class.pending).not_to include(submitted_sub)
    end
  end

  describe '.submitted scope' do
    it 'returns only submitted records' do
      submitted_sub = create(:formva40_1330m_submission, submission_status: 'submitted')
      pending_sub   = create(:formva40_1330m_submission, submission_status: 'pending')

      expect(described_class.submitted).to include(submitted_sub)
      expect(described_class.submitted).not_to include(pending_sub)
    end
  end

  describe '.failed scope' do
    it 'returns only failed records' do
      failed_sub  = create(:formva40_1330m_submission, submission_status: 'failed')
      pending_sub = create(:formva40_1330m_submission, submission_status: 'pending')

      expect(described_class.failed).to include(failed_sub)
      expect(described_class.failed).not_to include(pending_sub)
    end
  end

  # ---------------------------------------------------------------------------
  # Form data validator integration
  # ---------------------------------------------------------------------------
  describe 'form_data content validation' do
    let(:base_data) do
      {
        'serviceStatusAtDeath'     => 'activeDuty',
        'submitterRole'            => 'nextOfKin',
        'certificationAttestation' => true,
        'applicant' => {
          'name'         => { 'first' => 'Jane', 'last' => 'Doe' },
          'daytimePhone' => '5551234567',
          'email'        => 'jane@example.com',
          'address'      => {
            'street' => '1 Main St', 'city' => 'Arlington',
            'state' => 'VA', 'postalCode' => '22201', 'country' => 'USA'
          }
        },
        'decedent' => {
          'name'        => { 'first' => 'John', 'last' => 'Doe' },
          'ssn'         => '123456789',
          'dateOfBirth' => '1985-01-01',
          'dateOfDeath' => '2024-06-01',
          'placeOfDeath' => { 'city' => 'Washington', 'country' => 'USA' },
          'service'      => {
            'branchOfService'  => 'army',
            'component'        => 'active',
            'rankAtDeath'      => 'PFC',
            'serviceEntryDate' => '2004-01-01'
          }
        },
        'burialLocation' => {
          'cemeteryName'         => 'Test Cemetery',
          'cemeteryContactName'  => 'Test Contact',
          'cemeteryContactPhone' => '7031234567',
          'existingMarkerPresent' => 'noExistingMarker',
          'cemeteryAddress'      => {
            'street' => '1 Cemetery Rd', 'city' => 'Arlington',
            'state' => 'VA', 'postalCode' => '22211', 'country' => 'USA'
          }
        },
        'markerRequest' => { 'markerType' => 'flatGranite' },
        'documents'     => {
          'deathCertificate' => { 'confirmationCode' => 'uuid-cert' },
          'ddForm1300'       => { 'confirmationCode' => 'uuid-dd1300' }
        }
      }
    end

    it 'is valid with complete base data' do
      sub = build(:formva40_1330m_submission, form_data: base_data)
      expect(sub).to be_valid
    end

    it 'is invalid when certificationAttestation is false' do
      sub = build(:formva40_1330m_submission,
                  form_data: base_data.merge('certificationAttestation' => false))
      expect(sub).not_to be_valid
    end

    it 'is invalid with an SSN that does not match 9-digit pattern' do
      bad_data = base_data.deep_dup
      bad_data['decedent']['ssn'] = '12345'
      sub = build(:formva40_1330m_submission, form_data: bad_data)
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/ssn/i)
    end

    it 'is invalid when date of death precedes date of birth' do
      bad_data = base_data.deep_dup
      bad_data['decedent']['dateOfDeath'] = '1980-01-01'
      sub = build(:formva40_1330m_submission, form_data: bad_data)
      expect(sub).not_to be_valid
    end

    it 'is invalid for activeDuty when ddForm1300 is missing' do
      bad_data = base_data.deep_dup
      bad_data['documents'].delete('ddForm1300')
      sub = build(:formva40_1330m_submission, form_data: bad_data)
      expect(sub).not_to be_valid
      expect(sub.errors.full_messages.join).to match(/ddForm1300|DD Form 1300/i)
    end

    context 'guardOrReserve submission' do
      let(:guard_data) do
        data = base_data.deep_dup
        data['serviceStatusAtDeath']              = 'guardOrReserve'
        data['guardReserveQualifyingCircumstance'] = 'diedOnActiveDutyForTraining'
        data['documents'].delete('ddForm1300')
        data['documents']['ngbForm22'] = { 'confirmationCode' => 'uuid-ngb22' }
        data
      end

      it 'is valid with ngbForm22 present' do
        sub = build(:formva40_1330m_submission, form_data: guard_data)
        expect(sub).to be_valid
      end

      it 'is invalid without ngbForm22' do
        bad_data = guard_data.deep_dup
        bad_data['documents'].delete('ngbForm22')
        sub = build(:formva40_1330m_submission, form_data: bad_data)
        expect(sub).not_to be_valid
      end

      it 'is invalid without a qualifying circumstance' do
        bad_data = guard_data.deep_dup
        bad_data.delete('guardReserveQualifyingCircumstance')
        sub = build(:formva40_1330m_submission, form_data: bad_data)
        expect(sub).not_to be_valid
      end
    end
  end
end