# frozen_string_literal: true

# JSONAPI-compliant serializer for Formva401330mSubmission.
# Follows the ActiveModel::Serializer pattern used throughout vets-api.
class Formva401330mSerializer < ActiveModel::Serializer
  type 'formva40_1330m_submission'

  attributes :status,
             :confirmation_number,
             :submitted_at

  # --------------------------------------------------------------------------
  # status — human-readable label derived from submission_status column.
  # Maps the internal state machine values to API consumer-facing strings.
  # --------------------------------------------------------------------------
  def status
    case object.submission_status
    when 'pending'   then 'received'
    when 'submitted' then 'submitted'
    when 'failed'    then 'action_required'
    else                  'unknown'
    end
  end

  # --------------------------------------------------------------------------
  # confirmation_number — nil until the Lighthouse intake job completes.
  # --------------------------------------------------------------------------
  def confirmation_number
    object.confirmation_number
  end

  # --------------------------------------------------------------------------
  # submitted_at — ISO 8601 string or nil if not yet processed.
  # --------------------------------------------------------------------------
  def submitted_at
    object.submitted_at&.iso8601
  end
end