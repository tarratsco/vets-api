# frozen_string_literal: true

class CreateFormva401330mSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :formva40_1330m_submissions do |t|
      # Authenticated applicant identity (stored for audit trail)
      t.uuid   :user_uuid,           null: false

      # Encrypted form payload — AES-256 via attr_encrypted
      # The plain-text `form_data` column is intentionally omitted from the
      # schema; only the encrypted columns are persisted.
      t.text   :encrypted_form_data,     null: false
      t.text   :encrypted_form_data_iv,  null: false

      # Submission lifecycle
      t.string   :submission_status,    null: false, default: 'pending'
      t.string   :confirmation_number   # populated by Lighthouse on success
      t.datetime :submitted_at          # populated by Lighthouse job on success

      t.timestamps null: false
    end

    add_index :formva40_1330m_submissions, :user_uuid
    add_index :formva40_1330m_submissions, :submission_status
    add_index :formva40_1330m_submissions, :confirmation_number, unique: true, where: 'confirmation_number IS NOT NULL'
    add_index :formva40_1330m_submissions, :submitted_at
  end
end