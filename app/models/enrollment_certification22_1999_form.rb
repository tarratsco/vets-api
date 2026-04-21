# app/models/enrollment_certification22_1999_form.rb
# frozen_string_literal: true

# Plain Old Ruby Object (PORO) used for lightweight pre-validation
# before the submission record is persisted.
class EnrollmentCertification22_1999Form
  include ActiveModel::Model
  include ActiveModel::Validations

  attr_accessor :form_data, :user_uuid

  validates :user_uuid,  presence: true
  validates :form_data,  presence: true

  validate :form_data_is_valid_json, if: -> { form_data.present? }

  def initialize(attrs = {})
    # Accept either ActionController::Parameters or a Hash
    normalized = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs
    @form_data  = normalized.except('user_uuid').to_json
    @user_uuid  = normalized['user_uuid']
  end

  private

  def form_data_is_valid_json
    JSON.parse(form_data)
  rescue JSON::ParserError
    errors.add(:form_data, 'must be valid JSON')
  end
end