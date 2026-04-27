# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Formva401330mPdfGenerator do
  let(:valid_form_data) do
    {
      'serviceStatusAtDeath'     => 'activeDuty',
      'submitterRole'            => 'nextOfKin',
      'certificationAttestation' => true,
      'applicant' => {
        'name'         => { 'first' => 'Jane', 'middle' => 'M', 'last' => 'Doe' },
        'daytimePhone' => '5551234567',
        'email'        => 'jane@example.com',
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
        'placeOfDeath' => { 'city' => 'Washington', 'state' => 'DC', 'country' => 'USA' },
        'service'      => {
          'branchOfService'  => 'army',
          'component'        => 'active',
          'rankAtDeath'      => 'Sergeant',
          'serviceEntryDate' => '2005-06-01',
          'serviceEndDate'   => '2024-01-10'
        }
      },
      'burialLocation' => {
        'cemeteryName'         => 'Arlington National Cemetery',
        'cemeteryContactName'  => 'Cemetery Director',
        'cemeteryContactPhone' => '7035551234',
        'existingMarkerPresent' => 'noExistingMarker',
        'graveSection'         => 'Section 60',
        'graveLot'             => '123',
        'graveNumber'          => '4',
        'cemeteryAddress'      => {
          'street' => '1 Memorial Ave', 'city' => 'Arlington',
          'state' => 'VA', 'postalCode' => '22211', 'country' => 'USA'
        }
      },
      'markerRequest' => {
        'markerType'         => 'uprightGranite',
        'emblemOfBelief'     => 'Christianity',
        'personalInscription' => 'BELOVED SOLDIER'
      },
      'documents' => {
        'deathCertificate' => { 'confirmationCode' => 'abc-uuid' },
        'ddForm1300'       => { 'confirmationCode' => 'def-uuid' }
      }
    }
  end

  subject(:generator) { described_class.new(valid_form_data) }

  # ---------------------------------------------------------------------------
  # Instantiation
  # ---------------------------------------------------------------------------
  describe '#initialize' do
    it 'accepts a Hash of form_data' do
      expect { generator }.not_to raise_error
    end

    it 'defaults data to an empty hash for nil input' do
      gen = described_class.new(nil)
      expect(gen.instance_variable_get(:@data)).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # #generate — stub PdfFill to avoid needing the real PDF template in tests
  # ---------------------------------------------------------------------------
  describe '#generate' do
    let(:fake_pdf_path) { Rails.root.join('tmp', 'test_output_1330m.pdf').to_s }

    context 'when the PDF template exists and PdfFill succeeds' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with(described_class::TEMPLATE_PATH)
          .and_return(true)

        allow(PdfFill::Filler).to receive(:fill_form).and_return(fake_pdf_path)
      end

      it 'calls PdfFill::Filler.fill_form with the template path' do
        generator.generate
        expect(PdfFill::Filler).to have_received(:fill_form)
          .with(described_class::TEMPLATE_PATH, anything, flatten: true)
      end

      it 'returns the path returned by PdfFill::Filler' do
        result = generator.generate
        expect(result).to eq(fake_pdf_path)
      end
    end

    context 'when the PDF template does not exist' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with(described_class::TEMPLATE_PATH)
          .and_return(false)
      end

      it 'raises a GenerationError' do
        expect { generator.generate }.to raise_error(
          Formva401330mPdfGenerator::GenerationError,
          /PDF template not found/
        )
      end
    end

    context 'when PdfFill raises an error' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with(described_class::TEMPLATE_PATH)
          .and_return(true)
        allow(PdfFill::Filler).to receive(:fill_form)
          .and_raise(PdfFill::Filler::Error, 'encoding error')
      end

      it 'wraps the error in a GenerationError' do
        expect { generator.generate }.to raise_error(
          Formva401330mPdfGenerator::GenerationError,
          /PdfFill error/
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # mapped_data (private — tested via allow + spy on PdfFill)
  # ---------------------------------------------------------------------------
  describe 'field mapping (mapped_data)' do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with(described_class::TEMPLATE_PATH)
        .and_return(true)
    end

    let(:captured_mapped_data) do
      captured = nil
      allow(PdfFill::Filler).to receive(:fill_form) do |_template, data, _opts|
        captured = data
        'tmp/fake.pdf'
      end
      generator.generate
      captured
    end

    it 'maps APPLICANT_FIRST_NAME correctly' do
      expect(captured_mapped_data['APPLICANT_FIRST_NAME']).to eq('Jane')
    end

    it 'maps APPLICANT_LAST_NAME correctly' do
      expect(captured_mapped_data['APPLICANT_LAST_NAME']).to eq('Doe')
    end

    it 'maps DECEDENT_FIRST_NAME correctly' do
      expect(captured_mapped_data['DECEDENT_FIRST_NAME']).to eq('John')
    end

    it 'maps DECEDENT_SSN correctly' do
      expect(captured_mapped_data['DECEDENT_SSN']).to eq('123456789')
    end

    it 'maps DECEDENT_DATE_OF_BIRTH in MM/DD/YYYY format' do
      expect(captured_mapped_data['DECEDENT_DATE_OF_BIRTH']).to eq('06/15/1985')
    end

    it 'maps DECEDENT_DATE_OF_DEATH in MM/DD/YYYY format' do
      expect(captured_mapped_data['DECEDENT_DATE_OF_DEATH']).to eq('01/10/2024')
    end

    it 'maps SERVICE_BRANCH_OF_SERVICE correctly' do
      expect(captured_mapped_data['SERVICE_BRANCH_OF_SERVICE']).to eq('army')
    end

    it 'maps SERVICE_RANK_AT_DEATH correctly' do
      expect(captured_mapped_data['SERVICE_RANK_AT_DEATH']).to eq('Sergeant')
    end

    it 'maps CEMETERY_NAME correctly' do
      expect(captured_mapped_data['CEMETERY_NAME']).to eq('Arlington National Cemetery')
    end

    it 'maps MARKER_TYPE correctly' do
      expect(captured_mapped_data['MARKER_TYPE']).to eq('uprightGranite')
    end

    it 'maps PERSONAL_INSCRIPTION correctly' do
      expect(captured_mapped_data['PERSONAL_INSCRIPTION']).to eq('BELOVED SOLDIER')
    end

    it 'maps GRAVE_SECTION correctly' do
      expect(captured_mapped_data['GRAVE_SECTION']).to eq('Section 60')
    end

    it 'includes SUBMISSION_DATE as today in MM/DD/YYYY format' do
      expected = Date.current.strftime('%m/%d/%Y')
      expect(captured_mapped_data['SUBMISSION_DATE']).to eq(expected)
    end

    it 'sets SUBMISSION_SOURCE to VA.gov Digital Form' do
      expect(captured_mapped_data['SUBMISSION_SOURCE']).to eq('VA.gov Digital Form')
    end

    it 'does not include nil values (compact applied)' do
      expect(captured_mapped_data.values).not_to include(nil)
    end

    context 'with a nil serviceEndDate' do
      let(:data_no_end_date) do
        data = valid_form_data.deep_dup
        data['decedent']['service'].delete('serviceEndDate')
        data
      end

      it 'omits SERVICE_END_DATE from the mapped hash' do
        gen = described_class.new(data_no_end_date)
        captured = nil
        allow(PdfFill::Filler).to receive(:fill_form) do |_t, d, _o|
          captured = d
          'tmp/fake.pdf'
        end
        gen.generate
        expect(captured).not_to have_key('SERVICE_END_DATE')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Date formatting edge cases
  # ---------------------------------------------------------------------------
  describe 'date formatting' do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with(described_class::TEMPLATE_PATH)
        .and_return(true)
      allow(PdfFill::Filler).to receive(:fill_form).and_return('tmp/fake.pdf')
    end

    it 'returns nil for a blank date string' do
      gen = described_class.new({})
      # Access via generate and check; blank values are compact'd out
      expect { gen.generate }.not_to raise_error
    end

    it 'returns nil for a malformed date string without raising' do
      bad_data = valid_form_data.deep_dup
      bad_data['decedent']['dateOfBirth'] = 'not-a-date'
      gen = described_class.new(bad_data)
      captured = nil
      allow(PdfFill::Filler).to receive(:fill_form) { |_t, d, _o| captured = d; 'tmp/fake.pdf' }
      gen.generate
      expect(captured).not_to have_key('DECEDENT_DATE_OF_BIRTH')
    end
  end
end