# frozen_string_literal: true

# Service object wrapping PdfFill::Filler for VA Form 22-1999b.
# Invoked by Lighthouse::SubmitForm22_1999bJob before Benefits Intake upload.
# Generates a filled PDF from the form data and returns the path to the temp file.
#
# Prerequisites:
#   - lib/pdf_fill/forms/pdftk/VA22-1999b.pdf must be present (see Architecture Intent OQ-3)
#   - PdfFill::Forms::Va221999b mapper must be registered in PdfFill's form class map
class Form22_1999bPdfGenerator
  FORM_ID    = '22-1999b'
  STATS_KEY  = 'service.form22_1999b.pdf_generator'

  def initialize(form_data_hash)
    @form_data = form_data_hash.is_a?(Hash) ? form_data_hash : JSON.parse(form_data_hash)
  end

  # Generates the PDF and returns the path to the filled temp file.
  # The caller is responsible for deleting the file after use.
  #
  # @return [String] absolute path to the filled PDF
  # @raise [PdfGenerationError] if PDF generation fails
  def generate
    StatsD.measure("#{STATS_KEY}.duration") do
      StatsD.increment("#{STATS_KEY}.attempt")
      pdf_path = fill_pdf
      StatsD.increment("#{STATS_KEY}.success")
      pdf_path
    end
  rescue PdfFill::Filler::PdfFillerUnavailableError => e
    StatsD.increment("#{STATS_KEY}.filler_unavailable")
    raise PdfGenerationError, "PDF filler unavailable: #{e.message}"
  rescue StandardError => e
    StatsD.increment("#{STATS_KEY}.error")
    Sentry.capture_exception(e, extra: { form_id: FORM_ID })
    raise PdfGenerationError, "PDF generation failed: #{e.message}"
  end

  class PdfGenerationError < StandardError; end

  private

  def fill_pdf
    PdfFill::Filler.fill_form(
      form_id:   FORM_ID,
      form_data: @form_data
    )
  end
end