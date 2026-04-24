# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA102850E do
  # ── Shared test data ────────────────────────────────────────────────────────

  let(:minimal_data) do
    {
      'applicationType'      => 'initial',
      'occupationalCategory' => 'Certified Registered Nurse Anesthetist',
      'personalInformation'  => {
        'firstName'   => 'Jane',
        'lastName'    => 'Smith',
        'middleName'  => 'Marie',
        'dateOfBirth' => '1985-06-15',
        'ssn'         => '123-45-6789'
      },
      'contactInformation' => {
        'homeAddress' => {
          'street'  => '123 Main St',
          'city'    => 'Springfield',
          'state'   => 'IL',
          'zipCode' => '62701'
        },
        'primaryPhone'     => '555-867-5309',
        'professionalEmail' => 'jane.smith@example.com'
      },
      'professionalLicenses' => [
        {
          'licenseType'   => 'CRNA License',
          'issuingState'  => 'IL',
          'licenseNumber' => 'CRNA-IL-98765',
          'issueDate'     => '2020-01-01',
          'licenseStatus' => 'active'
        }
      ],
      'employmentHistory' => [
        {
          'employerName'  => 'Springfield General Hospital',
          'employerCity'  => 'Springfield',
          'employerState' => 'IL',
          'positionTitle' => 'Staff CRNA',
          'startDate'     => '2018-03-01'
        }
      ],
      'professionalReferences' => [
        {
          'firstName'        => 'Alice',
          'lastName'         => 'Jones',
          'professionalTitle' => 'Chief CRNA',
          'institution'      => 'Springfield General',
          'phone'            => '555-111-2222',
          'email'            => 'alice.jones@example.com',
          'relationship'     => 'direct-supervisor'
        },
        {
          'firstName'        => 'Bob',
          'lastName'         => 'Lee',
          'professionalTitle' => 'Anesthesiology Director',
          'institution'      => 'Memorial Hospital',
          'phone'            => '555-333-4444',
          'email'            => 'bob.lee@example.com',
          'relationship'     => 'department-chair'
        },
        {
          'firstName'        => 'Carol',
          'lastName'         => 'Park',
          'professionalTitle' => 'Program Director',
          'institution'      => 'State University CRNA Program',
          'phone'            => '555-555-6666',
          'email'            => 'carol.park@example.com',
          'relationship'     => 'training-program-director'
        }
      ],
      'adverseHistory' => {
        'adverseLicensureActions' => { 'hasAdverseLicensureActions' => false },
        'malpracticeHistory'      => { 'hasMalpracticeHistory' => false },
        'clinicalPrivilegesAdverse' => { 'hasAdversePrivilegesHistory' => false },
        'deaRegistrationAdverse'  => { 'hasAdverseDeaHistory' => false },
        'criminalHistory' => {
          'hasFelonyConviction'    => false,
          'hasMisdemeanorConviction' => false
        },
        'federalExclusion' => { 'isCurrentlyExcluded' => false }
      },
      'appointmentDetails' => {
        'facilityId'      => '636',
        'facilityName'    => 'Jesse Brown VA Medical Center',
        'positionTitle'   => 'Certified Registered Nurse Anesthetist',
        'appointmentType' => 'full-time-permanent'
      },
      'attestation' => {
        'certifiesAccuracy'                  => true,
        'authorizesBackgroundInvestigation'  => true,
        'authorizesReleaseOfInformation'     => true,
        'acknowledgesNpdbQuery'              => true,
        'electronicSignatureName'            => 'Jane Marie Smith',
        'signatureDate'                      => '2025-01-15'
      }
    }
  end

  let(:form) { described_class.new(minimal_data) }

  # ── Instantiation ───────────────────────────────────────────────────────────

  describe '#initialize' do
    it 'instantiates from a plain Hash without raising' do
      expect { described_class.new(minimal_data) }.not_to raise_error
    end

    it 'instantiates from ActionController::Parameters without raising' do
      params = ActionController::Parameters.new(minimal_data)
      expect { described_class.new(params) }.not_to raise_error
    end

    it 'stores data on the data attribute' do
      expect(form.data).to eq(minimal_data)
    end

    it 'exposes a signature_date set to current time' do
      freeze_time do
        instance = described_class.new(minimal_data)
        expect(instance.signature_date).to be_within(1.second).of(Time.current)
      end
    end
  end

  # ── STATS_KEY ───────────────────────────────────────────────────────────────

  describe 'STATS_KEY' do
    it 'has the correct value' do
      expect(described_class::STATS_KEY).to eq('api.simple_forms_api.10_2850e')
    end
  end

  # ── #metadata ───────────────────────────────────────────────────────────────

  describe '#metadata' do
    subject(:metadata) { form.metadata }

    it 'returns a Hash' do
      expect(metadata).to be_a(Hash)
    end

    it 'includes the applicant first name' do
      expect(metadata['veteranFirstName']).to eq('Jane')
    end

    it 'includes the applicant last name' do
      expect(metadata['veteranLastName']).to eq('Smith')
    end

    it 'includes the last four digits of the SSN as fileNumber' do
      expect(metadata['fileNumber']).to eq('6789')
    end

    it 'includes the home address zip code' do
      expect(metadata['zipCode']).to eq('62701')
    end

    it 'sets source to VA Platform Digital Forms' do
      expect(metadata['source']).to eq('VA Platform Digital Forms')
    end

    it 'sets docType to 10-2850e' do
      expect(metadata['docType']).to eq('10-2850e')
    end

    it 'sets businessLine to VHA' do
      expect(metadata['businessLine']).to eq('VHA')
    end

    context 'when personalInformation is missing' do
      let(:form) { described_class.new({}) }

      it 'returns empty strings for name and fileNumber without raising' do
        expect(metadata['veteranFirstName']).to eq('')
        expect(metadata['veteranLastName']).to eq('')
        expect(metadata['fileNumber']).to eq('')
      end
    end

    context 'when SSN has no dashes' do
      let(:data_no_dashes) do
        minimal_data.deep_merge('personalInformation' => { 'ssn' => '123456789' })
      end
      let(:form) { described_class.new(data_no_dashes) }

      it 'still extracts the last four digits' do
        expect(metadata['fileNumber']).to eq('6789')
      end
    end

    context 'when SSN is fewer than 4 characters' do
      let(:short_ssn_data) do
        minimal_data.deep_merge('personalInformation' => { 'ssn' => '123' })
      end
      let(:form) { described_class.new(short_ssn_data) }

      it 'returns an empty string for fileNumber' do
        expect(metadata['fileNumber']).to eq('')
      end
    end
  end

  # ── #desired_stamps ─────────────────────────────────────────────────────────

  describe '#desired_stamps' do
    it 'returns an Array' do
      expect(form.desired_stamps).to be_an(Array)
    end

    it 'returns an empty array (no PDF coordinate mapping confirmed yet)' do
      expect(form.desired_stamps).to be_empty
    end
  end

  # ── #submission_date_stamps ─────────────────────────────────────────────────

  describe '#submission_date_stamps' do
    let(:fixed_time) { Time.utc(2025, 1, 15, 14, 32, 7) }

    subject(:stamps) { form.submission_date_stamps(fixed_time) }

    it 'returns an Array' do
      expect(stamps).to be_an(Array)
    end

    it 'returns 6 stamp entries' do
      expect(stamps.length).to eq(6)
    end

    it 'each stamp has the required keys: coords, text, page, font_size' do
      stamps.each do |stamp|
        expect(stamp).to include(:coords, :text, :page, :font_size)
      end
    end

    it 'each stamp targets page 0' do
      stamps.each do |stamp|
        expect(stamp[:page]).to eq(0)
      end
    end

    it 'each stamp coords is a two-element Array' do
      stamps.each do |stamp|
        expect(stamp[:coords]).to be_an(Array).and have_attributes(length: 2)
      end
    end

    it 'each stamp x-coordinate is 395' do
      stamps.each do |stamp|
        expect(stamp[:coords].first).to eq(395)
      end
    end

    it 'each stamp uses font_size 10' do
      stamps.each do |stamp|
        expect(stamp[:font_size]).to eq(10)
      end
    end

    it 'includes the UTC submission timestamp in the stamp text' do
      timestamp_stamp = stamps.find { |s| s[:text].include?('UTC') }
      expect(timestamp_stamp).not_to be_nil
      expect(timestamp_stamp[:text]).to include('2025-01-15')
    end

    it 'uses default Time.current when no timestamp argument is given' do
      freeze_time do
        default_stamps = form.submission_date_stamps
        expect(default_stamps).to be_an(Array)
        expect(default_stamps).not_to be_empty
      end
    end
  end

  # ── #notification_first_name ────────────────────────────────────────────────

  describe '#notification_first_name' do
    it 'returns the applicant first name from personalInformation' do
      expect(form.notification_first_name).to eq('Jane')
    end

    it 'returns nil when personalInformation is absent' do
      expect(described_class.new({}).notification_first_name).to be_nil
    end
  end

  # ── #notification_email_address ─────────────────────────────────────────────

  describe '#notification_email_address' do
    it 'returns the professional email from contactInformation' do
      expect(form.notification_email_address).to eq('jane.smith@example.com')
    end

    it 'returns nil when contactInformation is absent' do
      expect(described_class.new({}).notification_email_address).to be_nil
    end
  end

  # ── #certifies_accuracy? ────────────────────────────────────────────────────

  describe '#certifies_accuracy?' do
    it 'returns true when attestation.certifiesAccuracy is true' do
      expect(form.certifies_accuracy?).to be true
    end

    it 'returns false when attestation.certifiesAccuracy is missing' do
      expect(described_class.new({}).certifies_accuracy?).to be false
    end
  end

  # ── #electronic_signature_name ──────────────────────────────────────────────

  describe '#electronic_signature_name' do
    it 'returns the typed electronic signature name' do
      expect(form.electronic_signature_name).to eq('Jane Marie Smith')
    end

    it 'returns nil when attestation is absent' do
      expect(described_class.new({}).electronic_signature_name).to be_nil
    end
  end

  # ── #signature_date_value ───────────────────────────────────────────────────

  describe '#signature_date_value' do
    it 'returns the ISO 8601 signature date string' do
      expect(form.signature_date_value).to eq('2025-01-15')
    end
  end

  # ── #target_facility_id ─────────────────────────────────────────────────────

  describe '#target_facility_id' do
    it 'returns the facility station ID' do
      expect(form.target_facility_id).to eq('636')
    end

    it 'returns nil when appointmentDetails is absent' do
      expect(described_class.new({}).target_facility_id).to be_nil
    end
  end

  # ── #application_type ───────────────────────────────────────────────────────

  describe '#application_type' do
    it 'returns initial for a new application' do
      expect(form.application_type).to eq('initial')
    end

    %w[reappointment transfer temporary].each do |type|
      it "returns #{type} when applicationType is #{type}" do
        data = minimal_data.merge('applicationType' => type)
        expect(described_class.new(data).application_type).to eq(type)
      end
    end
  end

  # ── #has_adverse_disclosures? ───────────────────────────────────────────────

  describe '#has_adverse_disclosures?' do
    context 'when all adverse history flags are false' do
      it 'returns false' do
        expect(form.has_adverse_disclosures?).to be false
      end
    end

    context 'when hasAdverseLicensureActions is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'adverseLicensureActions' => { 'hasAdverseLicensureActions' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when hasMalpracticeHistory is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'malpracticeHistory' => { 'hasMalpracticeHistory' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when hasAdversePrivilegesHistory is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'clinicalPrivilegesAdverse' => { 'hasAdversePrivilegesHistory' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when hasAdverseDeaHistory is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'deaRegistrationAdverse' => { 'hasAdverseDeaHistory' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when hasFelonyConviction is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'criminalHistory' => { 'hasFelonyConviction' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when hasMisdemeanorConviction is true' do
      let(:data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'criminalHistory' => { 'hasMisdemeanorConviction' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(data).has_adverse_disclosures?).to be true
      end
    end

    context 'when adverseHistory is entirely absent' do
      it 'returns false without raising' do
        expect(described_class.new({}).has_adverse_disclosures?).to be false
      end
    end
  end

  # ── #federally_excluded? ────────────────────────────────────────────────────

  describe '#federally_excluded?' do
    context 'when isCurrentlyExcluded is false' do
      it 'returns false' do
        expect(form.federally_excluded?).to be false
      end
    end

    context 'when isCurrentlyExcluded is true' do
      let(:excluded_data) do
        minimal_data.deep_merge(
          'adverseHistory' => {
            'federalExclusion' => { 'isCurrentlyExcluded' => true }
          }
        )
      end

      it 'returns true' do
        expect(described_class.new(excluded_data).federally_excluded?).to be true
      end
    end

    context 'when adverseHistory is entirely absent' do
      it 'returns false without raising' do
        expect(described_class.new({}).federally_excluded?).to be false
      end
    end
  end
end