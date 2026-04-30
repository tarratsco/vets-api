# frozen_string_literal: true

class Form27_2008Submission < ApplicationRecord
  FORM_ID = '27-2008'

  # Encrypted storage of full form data JSON.
  # Uses the platform-standard attr_encrypted pattern with KMS-managed key.
  # The plaintext form_data column is NOT persisted — only the encrypted columns.
  attr_encrypted :form_data,
                 key:        Settings.db_encryption_key,
                 algorithm:  'aes-256-cbc',
                 marshal:    true,
                 marshaler:  JSON,
                 dump_method: 'dump',
                 load_method: 'load'

  # Associations
  belongs_to :user_account, optional: true, primary_key: :uuid, foreign_key: :user_uuid

  # Validations
  validates :form_data, presence: true
  validates :encrypted_form_data, presence: true

  # Scopes
  scope :pending,    -> { where(submitted_at: nil) }
  scope :submitted,  -> { where.not(submitted_at: nil) }
  scope :for_user,   ->(uuid) { where(user_uuid: uuid) }

  # Callbacks
  before_create :set_confirmation_number

  # Returns a human-readable status string.
  def status
    submitted_at? ? 'submitted' : 'pending'
  end

  # True when the Benefits Intake API has acknowledged the submission.
  def submitted?
    submitted_at.present?
  end

  # Marks the record as submitted and persists.
  def mark_submitted!(confirmation_number = self.confirmation_number)
    update!(
      submitted_at: Time.current,
      confirmation_number: confirmation_number
    )
  end

  private

  def set_confirmation_number
    self.confirmation_number ||= generate_confirmation_number
  end

  def generate_confirmation_number
    timestamp = Time.current.strftime('%Y%m%d')
    random    = SecureRandom.hex(4).upcase
    "BF-#{timestamp}-#{random}"
  end
end