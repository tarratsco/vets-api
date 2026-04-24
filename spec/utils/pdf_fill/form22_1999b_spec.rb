# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PdfFill::Forms::Va221999b do
  subject(:mapper) { described_class.new }

  let(:base_form_data) do
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
        'effectiveDateOfChange' => '2024-10-01',
        'lastDateOfAttendance'  => '2024-09-30',
        'reasonForChange'       => 'medical'
      },
      'scoCertificationAttested' => true
    }
  end

  let(:merged_fields) { mapper.merge_fields(form_data: base_form_data) }

  describe '#merge_fields' do
    it 'returns a non-empty hash' do
      expect(merged_fields).to be_a(Hash).and be_present
    end

    it 'maps institution name to a PDF field' do
      institution_name_field = 'form1[0].#subform[0].InstitutionName[0]'
      expect(merged_fields[institution_name_field]).to eq('State University of Example')
    end

    it 'maps facility code to a PDF field' do
      facility_code_field = 'form1[0].#subform[0].FacilityCode[0]'
      expect(merged_fields[facility_code_field]).to eq('31000123')
    end

    it 'maps SCO first name to a PDF field' do
      expect(merged_fields['form1[0].#subform[0].SCOFirstName[0]']).to eq('Maria')
    end

    it 'maps student last name to a PDF field' do
      expect(merged_fields['form1[0].#subform[0].StudentLastName[0]']).to eq('Nguyen')
    end

    it 'maps only the last 4 digits of the student SSN' do
      ssn_last4_field = 'form1[0].#subform[0].StudentSSNLast4[0]'
      expect(merged_fields[ssn_last4_field]).to eq('6789')
      expect(merged_fields[ssn_last4_field]).not_to include('12345')
    end

    it 'does not write the full SSN anywhere in the output' do
      all_values = merged_fields.values.map(&:to_s)
      expect(all_values).not_to include('123456789')
    end

    it 'formats dates as MM/DD/YYYY' do
      effective_field = 'form1[0].#subform[0].EffectiveDateOfChange[0]'
      expect(merged_fields[effective_field]).to eq('10/01/2024')
    end

    it 'formats the original cert begin date as MM/DD/YYYY' do
      begin_date_field = 'form1[0].#subform[0].OrigCertBeginDate[0]'
      expect(merged_fields[begin_date_field]).to eq('08/19/2024')
    end

    it 'maps enrollment type to a human-readable label' do
      enrollment_type_field = 'form1[0].#subform[0].OrigEnrollmentType[0]'
      expect(merged_fields[enrollment_type_field]).to eq('Full Time')
    end

    it 'maps benefit chapter to a human-readable label' do
      benefit_chapter_field = 'form1[0].#subform[0].BenefitChapter[0]'
      expect(merged_fields[benefit_chapter_field]).to eq('Chapter 33 (Post-9/11 GI Bill)')
    end

    it 'maps type of change to a human-readable label' do
      type_field = 'form1[0].#subform[0].TypeOfChange[0]'
      expect(merged_fields[type_field]).to eq('Full Termination')
    end

    it 'maps scoCertificationAttested true to "Yes"' do
      attest_field = 'form1[0].#subform[0].SCOCertification[0]'
      expect(merged_fields[attest_field]).to eq('Yes')
    end

    context 'when scoCertificationAttested is false' do
      let(:base_form_data) do
        super().merge('scoCertificationAttested' => false)
      end

      it 'maps to nil' do
        attest_field = 'form1[0].#subform[0].SCOCertification[0]'
        expect(merged_fields[attest_field]).to be_nil
      end
    end

    context 'with correction type of change' do
      let(:correction_data) do
        base_form_data.deep_merge(
          'enrollmentChangeDetails' => {
            'typeOfChange'    => 'correction',
            'correctionDetails' => {
              'correctionItems' => %w[credit_hours enrollment_type]
            }
          }
        )
      end

      let(:merged_fields) { mapper.merge_fields(form_data: correction_data) }

      it 'maps correction items as a comma-separated string' do
        correction_field = 'form1[0].#subform[0].CorrectionItems[0]'
        expect(merged_fields[correction_field]).to eq('credit_hours, enrollment_type')
      end

      it 'maps type of change to Correction label' do
        type_field = 'form1[0].#subform[0].TypeOfChange[0]'
        expect(merged_fields[type_field]).to eq('Correction')
      end
    end

    context 'with partial withdrawal and updated enrollment details' do
      let(:partial_data) do
        base_form_data.deep_merge(
          'enrollmentChangeDetails' => {
            'typeOfChange'          => 'partial_withdrawal',
            'updatedEnrollmentDetails' => {
              'newCreditHours'    => 6,
              'newEnrollmentType' => 'half_time'
            }
          }
        )
      end

      let(:merged_fields) { mapper.merge_fields(form_data: partial_data) }

      it 'maps new credit hours' do
        new_hours_field = 'form1[0].#subform[0].NewCreditHours[0]'
        expect(merged_fields[new_hours_field]).to eq('6')
      end

      it 'maps new enrollment type to a human-readable label' do
        new_type_field = 'form1[0].#subform[0].NewEnrollmentType[0]'
        expect(merged_fields[new_type_field]).to eq('Half Time')
      end
    end

    context 'when a date value is nil' do
      let(:base_form_data) do
        super().deep_merge(
          'enrollmentChangeDetails' => { 'lastDateOfAttendance' => nil }
        )
      end

      it 'maps nil date to nil without raising' do
        last_attend_field = 'form1[0].#subform[0].LastDateOfAttendance[0]'
        expect(merged_fields[last_attend_field]).to be_nil
      end
    end

    context 'when a date value is malformed' do
      let(:base_form_data) do
        super().deep_merge(
          'enrollmentChangeDetails' => { 'effectiveDateOfChange' => 'not-a-date' }
        )
      end

      it 'maps malformed date to nil without raising' do
        effective_field = 'form1[0].#subform[0].EffectiveDateOfChange[0]'
        expect(merged_fields[effective_field]).to be_nil
      end
    end

    context 'with SCO phone formatting' do
      it 'formats 10-digit phone as (555) 867-5309' do
        phone_field = 'form1[0].#subform[0].SCOPhone[0]'
        expect(merged_fields[phone_field]).to eq('(555) 867-5309')
      end
    end
  end
end