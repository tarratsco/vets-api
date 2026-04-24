# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA102850D do
  # ---------------------------------------------------------------------------
  # Shared data fixtures
  # ---------------------------------------------------------------------------

  # Minimal valid flat-key payload (mirrors Architecture Intent Section 3.3)
  let(:flat_data) do
    {
      'firstName'                              => 'Ada',
      'lastName'                               => 'Lovelace',
      'middleName'                             => 'Augusta',
      'otherNamesUsed'                         => '',
      'presentAddressStreet1'                  => '123 Main St',
      'presentAddressStreet2'                  => '',
      'presentAddressCity'                     => 'Washington',
      'presentAddressState'                    => 'DC',
      'presentAddressZip'                      => '20001',
      'primaryPhone'                           => '2025550100',
      'alternatePhone'                         => '',
      'primaryEmail'                           => 'ada.lovelace@example.com',
      'alternateEmail'                         => '',
      'ssn'                                    => '900-12-3456',
      'dateOfBirth'                            => '1990-07-15',
      'vaTrainingFacilityCity'                 => 'Baltimore',
      'vaTrainingFacilityState'                => 'MD',
      'vaTrainingFacilityId'                   => '512',
      'vaTrainingStartDate'                    => '2026-07-01',
      'vaTrainingEndDate'                      => '2027-06-30',
      'everEmployedOrAffiliatedWithVaOrFederal' => 'N',
      'currentlyInUsMilitary'                  => 'N',
      'inReservesOrNationalGuard'              => 'N',
      'citizenshipStatus'                      => 'US_BIRTH',
      'countryOfCitizenship'                   => 'United States',
      'licenseActionHistory'                   => 'N',
      'clinicalPrivilegeActionHistory'         => 'N',
      'educationHistory'                       => [
        {
          'schoolName'       => 'Johns Hopkins University',
          'city'             => 'Baltimore',
          'state'            => 'MD',
          'zipCode'          => '21205',
          'startDate'        => '2010-08-01',
          'completionDate'   => '2014-05-15',
          'degreeType'       => 'MD',
          'majorFieldOfStudy' => 'Medicine'
        }
      ],
      'internationalMedicalSchoolGraduate'     => 'N',
      'medicaidFraudHistory'                   => 'N',
      'malpracticeHistory'                     => 'N',
      'traineeCertification'                   => true,
      'traineeCertificationDate'               => '2025-07-01',
      'authorizationInquiries'                 => true,
      'authorizationRelease'                   => true,
      'authorizationLiabilityRelease'          => true,
      'authorizationDisclose'                  => true,
      'authorizationShareAffiliated'           => true,
      'authorizationDate'                      => '2025-07-01'
    }
  end

  # Nested chapter-grouped payload variant (JSON Schema grouped structure)
  let(:nested_data) do
    {
      'applicantInformation' => {
        'firstName'           => 'Florence',
        'lastName'            => 'Nightingale',
        'primaryEmail'        => 'florence@example.com',
        'presentAddressZip'   => '90210'
      }
    }
  end

  # Minimal data without optional fields — used to exercise nil-safe accessors
  let(:sparse_data) do
    {
      'licenseActionHistory'         => 'N',
      'clinicalPrivilegeActionHistory' => 'N',
      'medicaidFraudHistory'         => 'N',
      'malpracticeHistory'           => 'N'
    }
  end

  # ---------------------------------------------------------------------------
  # Instantiation
  # ---------------------------------------------------------------------------
  describe '.new' do
    subject(:form) { described_class.new(flat_data) }

    it 'instantiates without error given a valid flat data hash' do
      expect { form }.not_to raise_error
    end

    it 'stores the data hash on the #data attribute' do
      expect(form.data).to eq(flat_data)
    end

    it 'sets @signature_date to a Time object in the Chicago timezone' do
      expect(form.signature_date).to be_a(ActiveSupport::TimeWithZone)
      expect(form.signature_date.time_zone.name).to eq('America/Chicago')
    end

    it 'accepts ActionController::Parameters and coerces to a plain Hash' do
      params = ActionController::Parameters.new(flat_data)
      expect { described_class.new(params) }.not_to raise_error
      expect(described_class.new(params).data).to eq(flat_data.with_indifferent_access)
    end

    it 'accepts nil data without raising (graceful degradation)' do
      expect { described_class.new(nil) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # STATS_KEY
  # ---------------------------------------------------------------------------
  describe '::STATS_KEY' do
    it 'equals the expected StatsD metric prefix' do
      expect(described_class::STATS_KEY).to eq('api.simple_forms_api.10_2850d')
    end
  end

  # ---------------------------------------------------------------------------
  # #metadata
  # ---------------------------------------------------------------------------
  describe '#metadata' do
    subject(:meta) { described_class.new(flat_data).metadata }

    it 'returns a Hash' do
      expect(meta).to be_a(Hash)
    end

    it 'includes the correct form_number' do
      expect(meta[:form_number]).to eq('10-2850D')
    end

    it 'includes veteran_first_name from the flat firstName key' do
      expect(meta[:veteran_first_name]).to eq('Ada')
    end

    it 'includes veteran_last_name from the flat lastName key' do
      expect(meta[:veteran_last_name]).to eq('Lovelace')
    end

    it 'includes zip_code from presentAddressZip' do
      expect(meta[:zip_code]).to eq('20001')
    end

    it 'includes station_id from vaTrainingFacilityId' do
      expect(meta[:station_id]).to eq('512')
    end

    it 'includes a receive_date in ISO8601 format' do
      expect(meta[:receive_date]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'sets source to "VA Platform Digital Forms"' do
      expect(meta[:source]).to eq('VA Platform Digital Forms')
    end

    it 'sets payload_version to "1"' do
      expect(meta[:payload_version]).to eq('1')
    end

    context 'when vaTrainingFacilityId is absent' do
      let(:data_without_facility_id) { flat_data.except('vaTrainingFacilityId') }

      subject(:meta) { described_class.new(data_without_facility_id).metadata }

      it 'falls back to "UNKNOWN" for station_id' do
        expect(meta[:station_id]).to eq('UNKNOWN')
      end
    end

    context 'when vaTrainingFacilityId is an empty string' do
      let(:data_blank_facility_id) { flat_data.merge('vaTrainingFacilityId' => '') }

      subject(:meta) { described_class.new(data_blank_facility_id).metadata }

      it 'falls back to "UNKNOWN" for station_id' do
        expect(meta[:station_id]).to eq('UNKNOWN')
      end
    end

    context 'with nested chapter-grouped data' do
      subject(:meta) { described_class.new(nested_data).metadata }

      it 'resolves veteran_first_name from the nested applicantInformation key' do
        expect(meta[:veteran_first_name]).to eq('Florence')
      end

      it 'resolves veteran_last_name from the nested applicantInformation key' do
        expect(meta[:veteran_last_name]).to eq('Nightingale')
      end

      it 'resolves zip_code from the nested applicantInformation key' do
        expect(meta[:zip_code]).to eq('90210')
      end
    end

    context 'with completely sparse data (no name or address fields)' do
      subject(:meta) { described_class.new(sparse_data).metadata }

      it 'returns nil for veteran_first_name without raising' do
        expect(meta[:veteran_first_name]).to be_nil
      end

      it 'returns nil for veteran_last_name without raising' do
        expect(meta[:veteran_last_name]).to be_nil
      end

      it 'falls back to "00000" for zip_code' do
        expect(meta[:zip_code]).to eq('00000')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #desired_stamps
  # ---------------------------------------------------------------------------
  describe '#desired_stamps' do
    subject(:form) { described_class.new(flat_data) }

    it 'returns an empty array' do
      expect(form.desired_stamps).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # #submission_date_stamps
  # ---------------------------------------------------------------------------
  describe '#submission_date_stamps' do
    let(:fixed_time) { Time.zone.parse('2026-07-01 14:30:00 UTC') }

    subject(:stamps) { described_class.new(flat_data).submission_date_stamps(fixed_time) }

    it 'returns an Array' do
      expect(stamps).to be_an(Array)
    end

    it 'returns exactly 5 stamp entries' do
      expect(stamps.length).to eq(5)
    end

    it 'each stamp has :coords, :text, :page, and :font_size keys' do
      stamps.each do |stamp|
        expect(stamp).to include(:coords, :text, :page, :font_size)
      end
    end

    it 'positions each stamp at x-coordinate 395' do
      stamps.each do |stamp|
        expect(stamp[:coords][0]).to eq(395)
      end
    end

    it 'assigns all stamps to page 0' do
      stamps.each do |stamp|
        expect(stamp[:page]).to eq(0)
      end
    end

    it 'uses font_size 10 for all stamps' do
      stamps.each do |stamp|
        expect(stamp[:font_size]).to eq(10)
      end
    end

    it 'includes the UTC submission timestamp in one of the stamp texts' do
      timestamp_stamp = stamps.find { |s| s[:text].include?('UTC') }
      expect(timestamp_stamp).not_to be_nil
      expect(timestamp_stamp[:text]).to include('2026-07-01')
    end

    it 'includes a "VA.gov Digital Form" reference in the first stamp text' do
      expect(stamps.first[:text]).to include('VA.gov Digital Form')
    end

    it 'uses Time.current as the default timestamp when none is provided' do
      freeze_time = Time.zone.parse('2026-07-01 09:00:00 UTC')
      travel_to(freeze_time) do
        default_stamps = described_class.new(flat_data).submission_date_stamps
        timestamp_stamp = default_stamps.find { |s| s[:text].include?('UTC') }
        expect(timestamp_stamp[:text]).to include('2026-07-01')
      end
    end

    it 'y-coordinates are in descending order (stamps stack top-to-bottom)' do
      y_coords = stamps.map { |s| s[:coords][1] }
      expect(y_coords).to eq(y_coords.sort.reverse)
    end
  end

  # ---------------------------------------------------------------------------
  # #notification_first_name
  # ---------------------------------------------------------------------------
  describe '#notification_first_name' do
    context 'with flat camelCase payload' do
      subject(:form) { described_class.new(flat_data) }

      it 'returns the firstName value' do
        expect(form.notification_first_name).to eq('Ada')
      end
    end

    context 'with nested chapter payload' do
      subject(:form) { described_class.new(nested_data) }

      it 'falls back to applicantInformation.firstName' do
        expect(form.notification_first_name).to eq('Florence')
      end
    end

    context 'when firstName is absent entirely' do
      subject(:form) { described_class.new(sparse_data) }

      it 'returns nil without raising' do
        expect(form.notification_first_name).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #notification_last_name
  # ---------------------------------------------------------------------------
  describe '#notification_last_name' do
    context 'with flat camelCase payload' do
      subject(:form) { described_class.new(flat_data) }

      it 'returns the lastName value' do
        expect(form.notification_last_name).to eq('Lovelace')
      end
    end

    context 'with nested chapter payload' do
      subject(:form) { described_class.new(nested_data) }

      it 'falls back to applicantInformation.lastName' do
        expect(form.notification_last_name).to eq('Nightingale')
      end
    end

    context 'when lastName is absent entirely' do
      subject(:form) { described_class.new(sparse_data) }

      it 'returns nil without raising' do
        expect(form.notification_last_name).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #notification_email_address
  # ---------------------------------------------------------------------------
  describe '#notification_email_address' do
    context 'with flat camelCase payload' do
      subject(:form) { described_class.new(flat_data) }

      it 'returns the primaryEmail value' do
        expect(form.notification_email_address).to eq('ada.lovelace@example.com')
      end
    end

    context 'with nested chapter payload' do
      subject(:form) { described_class.new(nested_data) }

      it 'falls back to applicantInformation.primaryEmail' do
        expect(form.notification_email_address).to eq('florence@example.com')
      end
    end

    context 'when primaryEmail is absent entirely' do
      subject(:form) { described_class.new(sparse_data) }

      it 'returns nil without raising' do
        expect(form.notification_email_address).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #should_send_to_point_of_contact?
  # ---------------------------------------------------------------------------
  describe '#should_send_to_point_of_contact?' do
    subject(:form) { described_class.new(flat_data) }

    it 'returns false (DEO notification handled outside the shared PoC path)' do
      expect(form.should_send_to_point_of_contact?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # FORM_NUMBER_MAP registration (integration smoke test)
  # ---------------------------------------------------------------------------
  describe 'FORM_NUMBER_MAP registration' do
    it 'maps "10-2850D" to the "vba_10_2850d" class name string' do
      expect(SimpleFormsApi::V1::UploadsController::FORM_NUMBER_MAP['10-2850D']).to eq('vba_10_2850d')
    end

    it 'resolves to this model class via safe_constantize' do
      class_name = 'SimpleFormsApi::' \
                   + SimpleFormsApi::V1::UploadsController::FORM_NUMBER_MAP['10-2850D']
                       .camelize
      expect(class_name.safe_constantize).to eq(described_class)
    end
  end
end