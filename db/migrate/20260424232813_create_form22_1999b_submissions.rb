# frozen_string_literal: true

class CreateForm22_1999bSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :form22_1999b_submissions do |t|
      # Encrypted form data columns (attr_encrypted pattern)
      # The plain form_data virtual attribute is never persisted directly;
      # attr_encrypted writes to encrypted_form_data + encrypted_form_data_iv.
      t.text :encrypted_form_data,    null: false
      t.text :encrypted_form_data_iv, null: false

      # Submitting user (vets-api User UUID — not a foreign key; users are
      # session-based and not stored in the vets-api database long-term)
      t.uuid :user_uuid

      # Processing state
      t.datetime :submitted_at

      # Lighthouse Benefits Intake confirmation GUID returned after successful upload
      t.string :confirmation_number

      # Error message written by the exhausted-retries Sidekiq callback
      # (max 500 chars — see SubmitForm22_1999bJob)
      t.string :submission_error, limit: 500

      # Timestamps
      t.timestamps null: false
    end

    add_index :form22_1999b_submissions, :user_uuid
    add_index :form22_1999b_submissions, :submitted_at
    add_index :form22_1999b_submissions, :confirmation_number, unique: true, where: 'confirmation_number IS NOT NULL'
  end
end