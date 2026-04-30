# frozen_string_literal: true

class Form27_2008Serializer < ActiveModel::Serializer
  type 'form27_2008_submission'

  attributes :status, :confirmation_number, :submitted_at

  # Return ISO 8601 string for submitted_at or nil if not yet submitted.
  def submitted_at
    object.submitted_at&.iso8601
  end

  # Delegate to the model's computed status string.
  def status
    object.status
  end

  # Confirmation number (auto-generated on create, updated on Benefits Intake
  # API acknowledgment via mark_submitted!).
  def confirmation_number
    object.confirmation_number
  end
end