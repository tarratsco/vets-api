# frozen_string_literal: true

class CreateForm272008Submissions < ActiveRecord::Migration[7.0]
  def change
    create_table :form27_2008_submissions do |t|
      # Encrypted form data storage (plaintext form_data is NOT persisted;
      # attr_encrypted reads/writes these two columns transparently).
      t.text   :encrypted_form_data,    null: false, comment: 'AES-256-CBC encrypted form payload'
      t.string :encrypted_form_data_iv, null: false, comment: 'Initialization vector for encrypted_form_data'

      # User association — nullable to support unauthenticated submissions.
      t.uuid   :user_uuid,    null: true, index: true, comment: 'UUID of authenticated submitting user; null for unauthenticated'

      # Submission lifecycle tracking.
      t.string   :confirmation_number, null: true,  index: { unique: true }, comment: 'Human-readable BF-YYYYMMDD-XXXXXXXX identifier'
      t.datetime :submitted_at,        null: true,  index: true, comment: 'Timestamp of successful Benefits Intake API acknowledgment; null = pending'

      # Standard Rails timestamps.
      t.timestamps null: false
    end

    # Composite index for user + pending submissions lookup.
    add_index :form27_2008_submissions, %i[user_uuid submitted_at], name: 'idx_form27_2008_user_pending'

    # Partial index for pending submissions queue (Sidekiq job polling).
    add_index :form27_2008_submissions, :created_at,
              where: 'submitted_at IS NULL',
              name: 'idx_form27_2008_pending_by_created_at'
  end
end