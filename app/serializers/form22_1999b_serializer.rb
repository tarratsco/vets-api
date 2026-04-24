# frozen_string_literal: true

class Form22_1999bSerializer
  include FastJsonapi::ObjectSerializer

  set_type :form22_1999b_submission

  # Core status and identification attributes surfaced to the client after
  # a successful POST /v0/form22_1999b submission.
  attributes :status, :confirmation_number, :submitted_at

  # status derives from whether the record has been processed by the
  # Lighthouse job (submitted_at is set) or is still pending.
  attribute :status do |record|
    record.submitted_at.present? ? 'submitted' : 'pending'
  end

  # submitted_at is serialized as ISO 8601 for consistent client parsing.
  attribute :submitted_at do |record|
    record.submitted_at&.iso8601
  end
end