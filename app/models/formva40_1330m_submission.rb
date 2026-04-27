# frozen_string_literal: true

# Stores a single VA Form 40-1330M submission attempt.
#
# Columns
#   id                       bigint pk
#   user_uuid                uuid       — authenticated applicant UUID
#   confirmation_number      string     — set by Lighthouse on successful intake
#   submission_status        string     — 'pending' | 'submitted' | 'failed'
#   encrypted_form_data      text       — AES-256 encrypted JSON blob
#   encrypted_form_data_iv   text       — initialisation vector for form_data
#   submitted_at             datetime   — set when Lighthouse intake succeeds
#   created_at / updated_at  datetime
class Formva401330mSubmission < ApplicationRecord
  # --------------------------------------------------------------------------
  # Encryption — mirrors the vets-api InProgressForm pattern.
  # Key is injected via Settings.db_encryption_key (vault-sourced).
  # --------------------------------------------------------------------------
  attr_encrypted :form_data,
                 key:        Settings.db_encryption_key,
                 marshal:    true,
                 marshaler:  JSON,
                 dump_method: 'dump',
                 load_method: 'restore'

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :form_data, presence: true
  validates :user_uuid,  presence: true
  validates :submission_status,
            inclusion: { in: %w[pending submitted failed] },
            allow_nil: false

  validates_with Formva401330mFormDataValidator

  # --------------------------------------------------------------------------
  # Scopes
  # --------------------------------------------------------------------------
  scope :pending,   -> { where(submission_status: 'pending') }
  scope :submitted, -> { where(submission_status: 'submitted') }
  scope :failed,    -> { where(submission_status: 'failed') }

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------
  before_validation :set_default_status, on: :create

  private

  def set_default_status
    self.submission_status ||= 'pending'
  end
end