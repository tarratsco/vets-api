# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA107959E do
  # ---------------------------------------------------------------------------
  # Shared fixture helpers
  # ---------------------------------------------------------------------------

  # Minimal valid payload — satisfies every required field so that model
  # methods do not blow up on nil digs. Tests that exercise optional /
  # conditional sections layer additional keys on top of this base.
  let(:minimal_data) do
    {
      'programSelection' => { 'program' => 'spina-bifida' },
      'patient' => {
        'firstName'   => 'Jane',
        'lastName'    => 'Doe',
        'middleInitial' => 'A',
        'ssn'         => '123-45-6789',
        'dateOfBirth' => '2005-03-15',
        'address'     => {
          'street'  => '123 Main St',
          'city'    => 'Springfield',
          'state'   => 'IL',
          'zipCode' => '62701'
        },
        'phone' => '(555) 867-5309'
      },
      'sponsor' => {
        'firstName' => 'John',
        'lastName'  => 'Doe',
        'ssn'       => '987-65-4321'
      },
      'claimType'          => ['travel'],
      'certificationSigner' => 'representative',
      'representative' => {
        'firstName' => 'Mary',
        'lastName'  => 'Doe'
      },
      'certification' => {
        'acknowledged' => true,
        'signature'    => 'Mary Doe',
        'date'         => '2025-06-01'
      }
    }
  end

  let(:cwvv_data) { minimal_data.merge('programSelection' => { 'program' => 'cwvv' }) }

  let(:patient_signer_data) do
    minimal_data.merge(
      'certificationSigner' => 'patient',
      'representative'      => {}
    )
  end

  let(:multi_claim_data) do
    minimal_data.merge('claimType' => %w[travel lodging meals other])
  end

  subject(:form) { described_class.new(minimal_data) }

  # ---------------------------------------------------------------------------
  # Class-level expectations
  # ---------------------------------------------------------------------------

  describe 'constants' do
    it 'exposes the correct STATS_KEY' do
      expect(described_class::STATS_KEY).to eq('api.simple_forms_api.10_7959e')
    end
  end

  # ---------------------------------------------------------------------------
  # Instantiation
  # ---------------------------------------------------------------------------

  describe '#initialize' do
    it 'instantiates without error given minimal valid data' do
      expect { described_class.new(minimal_data) }.not_to raise_error
    end

    it 'stores the data hash on #data' do
      expect(form.data).to eq(minimal_data)
    end

    it 'sets @signature_date to a Time object in Chicago timezone' do
      expect(form.signature_date).to be_a(ActiveSupport::TimeWithZone)
      expect(form.signature_date.time_zone.name).to eq('America/Chicago')
    end

    it 'accepts ActionController::Parameters by converting to unsafe hash' do
      params = ActionController::Parameters.new(minimal_data)
      expect { described_class.new(params) }.not_to raise_error
    end

    it 'handles nil data gracefully' do
      # BaseForm converts nil to empty hash in subclasses that call super
      expect { described_class.new(nil) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # #metadata
  # ---------------------------------------------------------------------------

  describe '#metadata' do
    subject(:meta) { form.metadata }

    it 'returns a Hash' do
      expect(meta).to be_a(Hash)
    end

    it 'includes the patient first and last name as veteranFirstName / veteranLastName' do
      expect(meta['veteranFirstName']).to eq('Jane')
      expect(meta['veteranLastName']).to eq('Doe')
    end

    it 'includes the sponsor first and last name' do
      expect(meta['sponsorFirstName']).to eq('John')
      expect(meta['sponsorLastName']).to eq('Doe')
    end

    it 'includes the program selection' do
      expect(meta['programSelection']).to eq('spina-bifida')
    end

    it 'includes the claimType array' do
      expect(meta['claimType']).to eq(['travel'])
    end

    it 'includes the patient zip code' do
      expect(meta['zipCode']).to eq('62701')
    end

    it 'sets docType to 10-7959E' do
      expect(meta['docType']).to eq('10-7959E')
    end

    it 'sets source to VA Platform Digital Forms' do
      expect(meta['source']).to eq('VA Platform Digital Forms')
    end

    it 'sets fileNumber to nil (no VA file number for OIVC programs)' do
      expect(meta['fileNumber']).to be_nil
    end

    it 'generates a UUID for the uuid key' do
      expect(meta['uuid']).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'includes a receiveDt timestamp string' do
      expect(meta['receiveDt']).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)
    end

    context 'when claimType has multiple values' do
      subject(:meta) { described_class.new(multi_claim_data).metadata }

      it 'includes all claim types' do
        expect(meta['claimType']).to contain_exactly('travel', 'lodging', 'meals', 'other')
      end
    end

    context 'when programSelection is cwvv' do
      subject(:meta) { described_class.new(cwvv_data).metadata }

      it 'reflects the cwvv program' do
        expect(meta['programSelection']).to eq('cwvv')
      end
    end

    context 'when patient data is missing' do
      subject(:meta) { described_class.new({}).metadata }

      it 'returns nil for patient fields without raising' do
        expect(meta['veteranFirstName']).to be_nil
        expect(meta['veteranLastName']).to be_nil
        expect(meta['zipCode']).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #desired_stamps
  # ---------------------------------------------------------------------------

  describe '#desired_stamps' do
    subject(:stamps) { form.desired_stamps }

    it 'returns an Array' do
      expect(stamps).to be_an(Array)
    end

    it 'is not empty (program label stamp must be present)' do
      expect(stamps).not_to be_empty
    end

    it 'each stamp has the required keys: coords, text, page, font_size' do
      stamps.each do |stamp|
        expect(stamp).to include(:coords, :text, :page, :font_size)
      end
    end

    it 'each stamp has a two-element coords array' do
      stamps.each do |stamp|
        expect(stamp[:coords].length).to eq(2)
      end
    end

    it 'each stamp targets page 0' do
      stamps.each do |stamp|
        expect(stamp[:page]).to eq(0)
      end
    end

    context 'when program is spina-bifida' do
      it 'stamps the Spina Bifida program label' do
        program_stamp = stamps.find { |s| s[:text].include?('Program:') }
        expect(program_stamp[:text]).to include('Spina Bifida Health Care Benefits Program')
      end
    end

    context 'when program is cwvv' do
      subject(:stamps) { described_class.new(cwvv_data).desired_stamps }

      it 'stamps the CWVV program label' do
        program_stamp = stamps.find { |s| s[:text].include?('Program:') }
        expect(program_stamp[:text]).to include('Children of Women Vietnam Veterans')
      end
    end

    context 'when program is unknown / missing' do
      subject(:stamps) { described_class.new({}).desired_stamps }

      it 'stamps Unknown Program without raising' do
        program_stamp = stamps.find { |s| s[:text].include?('Program:') }
        expect(program_stamp[:text]).to include('Unknown Program')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #submission_date_stamps
  # ---------------------------------------------------------------------------

  describe '#submission_date_stamps' do
    let(:fixed_time) { Time.utc(2025, 6, 1, 14, 30, 0) }

    subject(:stamps) { form.submission_date_stamps(fixed_time) }

    it 'returns an Array' do
      expect(stamps).to be_an(Array)
    end

    it 'returns exactly 5 stamps' do
      expect(stamps.length).to eq(5)
    end

    it 'each stamp has the required keys: coords, text, page, font_size' do
      stamps.each do |stamp|
        expect(stamp).to include(:coords, :text, :page, :font_size)
      end
    end

    it 'includes the submission channel text on the first stamp' do
      expect(stamps.first[:text]).to include('VA.gov Digital Form')
    end

    it 'includes the form version identifier' do
      form_version_stamp = stamps.find { |s| s[:text].include?('10-7959E') }
      expect(form_version_stamp).not_to be_nil
    end

    it 'includes the UTC timestamp derived from the provided timestamp' do
      utc_stamp = stamps.find { |s| s[:text].include?('UTC') }
      expect(utc_stamp[:text]).to include('2025-06-01')
    end

    it 'uses the current time when no timestamp argument is given' do
      freeze_time = Time.utc(2025, 7, 4, 10, 0, 0)
      travel_to(freeze_time) do
        stamps_no_arg = form.submission_date_stamps
        utc_stamp = stamps_no_arg.find { |s| s[:text].include?('UTC') }
        expect(utc_stamp[:text]).to include('2025-07-04')
      end
    end

    it 'all stamps target page 0' do
      stamps.each do |stamp|
        expect(stamp[:page]).to eq(0)
      end
    end

    it 'all stamps use font_size 10' do
      stamps.each do |stamp|
        expect(stamp[:font_size]).to eq(10)
      end
    end

    it 'all stamps have x coordinate of 395 (right-margin box position)' do
      stamps.each do |stamp|
        expect(stamp[:coords].first).to eq(395)
      end
    end

    it 'stamps have descending y coordinates (top-to-bottom layout)' do
      y_coords = stamps.map { |s| s[:coords].last }
      expect(y_coords).to eq(y_coords.sort.reverse)
    end
  end

  # ---------------------------------------------------------------------------
  # #notification_first_name
  # ---------------------------------------------------------------------------

  describe '#notification_first_name' do
    context 'when certificationSigner is representative' do
      it "returns the representative's firstName" do
        expect(form.notification_first_name).to eq('Mary')
      end
    end

    context 'when certificationSigner is patient' do
      subject(:form) { described_class.new(patient_signer_data) }

      it "returns the patient's firstName" do
        expect(form.notification_first_name).to eq('Jane')
      end
    end

    context 'when certificationSigner is missing' do
      subject(:form) { described_class.new(minimal_data.except('certificationSigner')) }

      it 'falls back to patient firstName (non-representative path)' do
        expect(form.notification_first_name).to eq('Jane')
      end
    end

    context 'when all data is missing' do
      subject(:form) { described_class.new({}) }

      it 'returns nil without raising' do
        expect(form.notification_first_name).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #notification_email_address
  # ---------------------------------------------------------------------------

  describe '#notification_email_address' do
    it 'returns nil (email sourced from authenticated session, not form payload)' do
      expect(form.notification_email_address).to be_nil
    end

    it 'returns nil even when data includes arbitrary email-like keys' do
      data_with_email = minimal_data.merge('email' => 'claimant@example.com')
      expect(described_class.new(data_with_email).notification_email_address).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # FORM_NUMBER_MAP registration (integration guard)
  #
  # Verifies that the uploads controller's dispatch table includes the new
  # form number so that a POST /v1/simple_forms with form_number: '10-7959E'
  # resolves to this model class. This test will fail if the FORM_NUMBER_MAP
  # patch is not applied, providing an automated gate in CI.
  # ---------------------------------------------------------------------------

  describe 'FORM_NUMBER_MAP registration' do
    it 'maps 10-7959E to vba_10_7959e in the uploads controller' do
      map = SimpleFormsApi::V1::UploadsController::FORM_NUMBER_MAP
      expect(map['10-7959E']).to eq('vba_10_7959e')
    end

    it 'resolves vba_10_7959e to this model class via safe_constantize' do
      class_name = 'SimpleFormsApi::VBA107959E'
      expect(class_name.safe_constantize).to eq(described_class)
    end
  end
end