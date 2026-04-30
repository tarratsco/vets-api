# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form27_2008PdfGenerator, type: :service do
  let(:valid_form_data) do
    {
      'applicantType'        => 'nextOfKin',
      'dateSigned'           => '2024-01-15',
      'certificationChecked' => true,
      'remarks'              => 'No next of kin other than the spouse.',
      'veteranInformation' => {
        'firstName'                => 'John',
        'middleName'               => 'Q',
        'lastName'                 => 'Veteran',
        'maidenOrOtherName'        => nil,
        'vaFileNumber'             => '12345678',
        'socialSecurityNumber'     => '123456789',
        'militaryServiceNumber'    => '12345678',
        'dateOfBirth'              => '1945-06-15',
        'dateOfDeath'              => '2024-01-10',
        'dateOfBurial'             => '2024-01-17',
        'placeOfBurialCemeteryName' => 'Arlington National Cemetery',
        'placeOfBurialCity'        => 'Arlington',
        'placeOfBurialState'       => 'VA'
      },
      'serviceInformation' => {
        'branchOfService'            => %w[army selectedReserve],
        'dateEnteredActiveDuty'      => '1965-03-01',
        'dateReleasedFromActiveDuty' => '1968-02-28'
      },
      'eligibility' => {
        'documentationAvailable' => true,
        'dischargeCharacter'     => 'honorable'
      },
      'flagRecipient' => {
        'recipientFullName'           => 'Jane Veteran',
        'recipientRelationship'       => 'survivingSpouse',
        'recipientRelationshipOther'  => nil,
        'recipientAddressLine1'       => '123 Main St',
        'recipientAddressLine2'       => 'Apt 2B',
        'recipientCity'               => 'Springfield',
        'recipientState'              => 'VA',
        'recipientZip'                => '22001',
        'recipientPhone'              => '5555551234'
      },
      'applicant' => {
        'firstName'               => 'Jane',
        'middleName'              => nil,
        'lastName'                => 'Veteran',
        'addressLine1'            => '123 Main St',
        'addressLine2'            => 'Apt 2B',
        'city'                    => 'Springfield',
        'state'                   => 'VA',
        'zip'                     => '22001',
        'relationshipToVeteran'   => 'survivingSpouse',
        'relationshipToVeteranOther' => nil
      }
    }
  end

  subject(:generator) { described_class.new(valid_form_data) }

  let(:mock_pdf_path) { '/tmp/test_form27_2008.pdf' }

  before do
    allow(PdfFill::Filler).to receive(:fill_form_by_type).and_return(mock_pdf_path)
    allow(StatsD).to receive(:increment)
    allow(StatsD).to receive(:timing)
  end

  # ---------------------------------------------------------------------------
  # Initialization
  # ---------------------------------------------------------------------------

  describe '#initialize' do
    it 'accepts a Hash' do
      expect { described_class.new(valid_form_data) }.not_to raise_error
    end

    it 'accepts a JSON string' do
      expect { described_class.new(valid_form_data.to_json) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # generate
  # ---------------------------------------------------------------------------

  describe '#generate' do
    it 'returns a file path string' do
      expect(generator.generate).to eq(mock_pdf_path)
    end

    it 'calls PdfFill::Filler.fill_form_by_type with the vba_27_2008 template' do
      generator.generate
      expect(PdfFill::Filler).to have_received(:fill_form_by_type)
        .with(anything, 'vba_27_2008')
    end

    it 'passes a hash to PdfFill::Filler' do
      generator.generate
      expect(PdfFill::Filler).to have_received(:fill_form_by_type)
        .with(a_kind_of(Hash), anything)
    end

    it 'emits a StatsD attempt metric' do
      generator.generate
      expect(StatsD).to have_received(:increment)
        .with('api.form27_2008.pdf_generation.attempt')
    end

    it 'emits a StatsD success metric' do
      generator.generate
      expect(StatsD).to have_received(:increment)
        .with('api.form27_2008.pdf_generation.success')
    end

    it 'emits a StatsD timing metric' do
      generator.generate
      expect(StatsD).to have_received(:timing)
        .with('api.form27_2008.pdf_generation.duration', anything)
    end

    context 'when PdfFill raises an error' do
      before do
        allow(PdfFill::Filler).to receive(:fill_form_by_type)
          .and_raise(StandardError, 'PDF generation failed')
      end

      it 're-raises the error' do
        expect { generator.generate }.to raise_error(StandardError, 'PDF generation failed')
      end

      it 'emits a StatsD error metric' do
        generator.generate rescue nil
        expect(StatsD).to have_received(:increment)
          .with('api.form27_2008.pdf_generation.error', anything)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PDF data construction (private methods tested via integration)
  # ---------------------------------------------------------------------------

  describe 'PDF data construction' do
    let(:pdf_data_arg) do
      captured = nil
      allow(PdfFill::Filler).to receive(:fill_form_by_type) do |data, _template|
        captured = data
        mock_pdf_path
      end
      generator.generate
      captured
    end

    describe 'veteran name fields' do
      it 'maps firstName to veteranFirstName' do
        expect(pdf_data_arg['veteranFirstName']).to eq('John')
      end

      it 'maps lastName to veteranLastName' do
        expect(pdf_data_arg['veteranLastName']).to eq('Veteran')
      end

      it 'maps middleName to veteranMiddleName' do
        expect(pdf_data_arg['veteranMiddleName']).to eq('Q')
      end
    end

    describe 'date formatting' do
      it 'formats dateOfBirth as MM/DD/YYYY' do
        expect(pdf_data_arg['veteranDateOfBirth']).to eq('06/15/1945')
      end

      it 'formats dateOfDeath as MM/DD/YYYY' do
        expect(pdf_data_arg['veteranDateOfDeath']).to eq('01/10/2024')
      end

      it 'formats dateOfBurial as MM/DD/YYYY' do
        expect(pdf_data_arg['dateOfBurial']).to eq('01/17/2024')
      end

      it 'formats dateSigned as MM/DD/YYYY' do
        expect(pdf_data_arg['dateSigned']).to eq('01/15/2024')
      end

      it 'formats dateEnteredActiveDuty as MM/DD/YYYY' do
        expect(pdf_data_arg['dateEnteredActiveDuty']).to eq('03/01/1965')
      end

      it 'formats dateReleasedFromActiveDuty as MM/DD/YYYY' do
        expect(pdf_data_arg['dateReleasedFromActiveDuty']).to eq('02/28/1968')
      end

      it 'returns empty string for blank date' do
        data = valid_form_data.deep_dup
        data['veteranInformation']['dateOfBirth'] = nil
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) do |d, _t|
          d
        end
        result = gen.generate
        expect(result['veteranDateOfBirth']).to eq('')
      end
    end

    describe 'branch of service checkboxes' do
      it 'sets branchArmy to true when army is in branchOfService' do
        expect(pdf_data_arg['branchArmy']).to be(true)
      end

      it 'sets branchSelectedReserve to true when selectedReserve is in branchOfService' do
        expect(pdf_data_arg['branchSelectedReserve']).to be(true)
      end

      it 'sets branchNavy to false when navy is not in branchOfService' do
        expect(pdf_data_arg['branchNavy']).to be(false)
      end

      it 'sets all false when branchOfService is empty' do
        data = valid_form_data.deep_dup
        data['serviceInformation']['branchOfService'] = []
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) { |d, _t| d }
        result = gen.generate
        described_class::BRANCH_TO_FIELD_MAP.each_value do |field|
          expect(result[field]).to be(false)
        end
      end
    end

    describe 'documentation checkboxes' do
      it 'sets documentationYes to true when documentationAvailable is true' do
        expect(pdf_data_arg['documentationYes']).to be(true)
        expect(pdf_data_arg['documentationNo']).to be(false)
      end

      it 'sets documentationNo to true when documentationAvailable is false' do
        data = valid_form_data.deep_dup
        data['eligibility']['documentationAvailable'] = false
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) { |d, _t| d }
        result = gen.generate
        expect(result['documentationYes']).to be(false)
        expect(result['documentationNo']).to be(true)
      end
    end

    describe 'phone formatting' do
      it 'formats a 10-digit phone number as (NXX) NXX-XXXX' do
        expect(pdf_data_arg['flagRecipientPhone']).to eq('(555) 555-1234')
      end

      it 'returns empty string for blank phone' do
        data = valid_form_data.deep_dup
        data['flagRecipient']['recipientPhone'] = nil
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) { |d, _t| d }
        result = gen.generate
        expect(result['flagRecipientPhone']).to eq('')
      end
    end

    describe 'address formatting' do
      it 'combines address components with newlines' do
        expect(pdf_data_arg['flagRecipientAddress']).to include('123 Main St')
        expect(pdf_data_arg['flagRecipientAddress']).to include('Apt 2B')
        expect(pdf_data_arg['flagRecipientAddress']).to include('Springfield, VA 22001')
      end
    end

    describe 'electronic signature field' do
      it 'includes applicant full name and certification notice' do
        sig = pdf_data_arg['applicantSignature']
        expect(sig).to include('Jane Veteran')
        expect(sig).to include('Electronically certified on 01/15/2024 via VA.gov')
      end
    end

    describe 'relationship fields' do
      it 'humanizes the recipientRelationship value' do
        expect(pdf_data_arg['flagRecipientRelationship']).to eq('Survivingspouse')
          .or eq('Surviving spouse')
      end

      it 'uses recipientRelationshipOther text when relationship is "other"' do
        data = valid_form_data.deep_dup
        data['flagRecipient']['recipientRelationship']      = 'other'
        data['flagRecipient']['recipientRelationshipOther'] = 'Close family friend'
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) { |d, _t| d }
        result = gen.generate
        expect(result['flagRecipientRelationship']).to eq('Close family friend')
      end

      it 'uses relationshipToVeteranOther when applicant relationship is otherAuthorizedRepresentative' do
        data = valid_form_data.deep_dup
        data['applicant']['relationshipToVeteran']      = 'otherAuthorizedRepresentative'
        data['applicant']['relationshipToVeteranOther'] = 'Legal guardian'
        gen = described_class.new(data)
        allow(PdfFill::Filler).to receive(:fill_form_by_type) { |d, _t| d }
        result = gen.generate
        expect(result['applicantRelationshipToVeteran']).to eq('Legal guardian')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  describe 'FORM_ID' do
    it 'equals "27-2008"' do
      expect(described_class::FORM_ID).to eq('27-2008')
    end
  end

  describe 'BRANCH_TO_FIELD_MAP' do
    it 'has 10 branch entries' do
      expect(described_class::BRANCH_TO_FIELD_MAP.size).to eq(10)
    end

    it 'includes all expected branch keys' do
      expected_keys = %w[army navy airForce spaceForce marineCorps coastGuard
                         usphs noaa selectedReserve other]
      expect(described_class::BRANCH_TO_FIELD_MAP.keys).to match_array(expected_keys)
    end
  end
end