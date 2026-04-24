# frozen_string_literal: true

class Form22_1999bSubmission < ApplicationRecord
  self.table_name = 'form22_1999b_submissions'

  # Encrypt the raw form data JSON at rest using attr_encrypted pattern
  # consistent with other vets-api submission models.
  # The encrypted_form_data and encrypted_form_data_iv columns are written by
  # attr_encrypted; the plain form_data virtual attribute is used in application code.
  attr_encrypted :form_data,
                 key:       Settings.db_encryption_key,
                 algorithm: 'aes-256-cbc',
                 mode:      :single_iv_and_salt

  # -----------------------------------------------------------------------
  # Validations
  # -----------------------------------------------------------------------
  validates :form_data, presence: true

  # -----------------------------------------------------------------------
  # Scopes
  # -----------------------------------------------------------------------
  scope :pending,   -> { where(submitted_at: nil) }
  scope :submitted, -> { where.not(submitted_at: nil) }

  # -----------------------------------------------------------------------
  # Instance helpers
  # -----------------------------------------------------------------------

  # Returns the confirmation number generated after Lighthouse intake succeeds.
  # Stored as the guid returned by the Benefits Intake API.
  def confirmation_number
    read_attribute(:confirmation_number)
  end

  # Marks the submission as submitted, recording the Lighthouse GUID and timestamp.
  def mark_submitted!(intake_guid)
    update!(
      confirmation_number: intake_guid,
      submitted_at:        Time.current
    )
  end

  # Returns parsed form data as a HashWithIndifferentAccess.
  def parsed_form_data
    JSON.parse(form_data).with_indifferent_access
  rescue JSON::ParserError
    {}.with_indifferent_access
  end

  # Convenience accessor for the form model wrapper.
  def form_model
    @form_model ||= SimpleFormsApi::VBA221999b.new(parsed_form_data)
  end
end