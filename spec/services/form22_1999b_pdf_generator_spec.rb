# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form22_1999bPdfGenerator do
  let(:form_data) do
    {
      'institutionAndScoInformation' => {
        'facilityCode'    => '31000123',
        'institutionName' => 'State University of Example',
        'scoFirstName'    => 'Maria',
        'scoLastName'     => 'Hernandez',
        'scoPhone'        => '5558675309',
        'scoEmail'        => 'certifying.official@university.edu'
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

  subject(:generator) { described_class.new(form_data) }

  describe '#generate' do
    context 'when PdfFill::Filler succeeds' do
      let(:pdf_path) { '/tmp/va_22_1999b_filled.pdf' }

      before do
        allow(PdfFill::Filler).to receive(:fill_form).and_return(pdf_path)
      end

      it 'returns the path to the filled PDF' do
        expect(generator.generate).to eq(pdf_path)
      end

      it 'calls PdfFill::Filler with the correct form_id' do
        expect(PdfFill::Filler).to receive(:fill_form).with(
          hash_including(form_id: '22-1999b')
        )
        generator.generate
      end

      it 'increments the StatsD attempt counter' do
        expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.attempt")
        expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.success")
        generator.generate
      end
    end

    context 'when PdfFill::Filler is unavailable' do
      before do
        allow(PdfFill::Filler).to receive(:fill_form)
          .and_raise(PdfFill::Filler::PdfFillerUnavailableError, 'pdftk not found')
      end

      it 'raises PdfGenerationError' do
        expect { generator.generate }.to raise_error(
          described_class::PdfGenerationError, /PDF filler unavailable/
        )
      end

      it 'increments the filler_unavailable StatsD counter' do
        expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.filler_unavailable")
        generator.generate rescue nil # rubocop:disable Style/RescueModifier
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(PdfFill::Filler).to receive(:fill_form)
          .and_raise(StandardError, 'unexpected failure')
      end

      it 'raises PdfGenerationError' do
        expect { generator.generate }.to raise_error(
          described_class::PdfGenerationError, /PDF generation failed/
        )
      end

      it 'reports the error to Sentry' do
        expect(Sentry).to receive(:capture_exception)
        generator.generate rescue nil # rubocop:disable Style/RescueModifier
      end

      it 'increments the error StatsD counter' do
        expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.error")
        generator.generate rescue nil # rubocop:disable Style/RescueModifier
      end
    end

    context 'when initialized with a JSON string instead of a Hash' do
      subject(:generator) { described_class.new(form_data.to_json) }
      let(:pdf_path)       { '/tmp/va_22_1999b_string_init.pdf' }

      before do
        allow(PdfFill::Filler).to receive(:fill_form).and_return(pdf_path)
      end

      it 'parses the JSON string and generates without error' do
        expect { generator.generate }.not_to raise_error
      end

      it 'returns the pdf path' do
        expect(generator.generate).to eq(pdf_path)
      end
    end
  end
end