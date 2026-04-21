# config/routes/22_1999.rb
# frozen_string_literal: true

# VA Form 22-1999 — Enrollment Certification routes
# Mounted under the primary /v0 namespace in config/routes.rb via:
#   draw :22_1999
#
# Facility code institution lookup and Yellow Ribbon lookup routes are
# also defined here since they are consumed exclusively by this form.

Rails.application.routes.draw do
  namespace :v0 do
    namespace :education do
      # -----------------------------------------------------------------------
      # Enrollment Certifications — primary form submission resource
      # POST   /v0/education/enrollment_certifications        → create
      # GET    /v0/education/enrollment_certifications/:id    → show
      # -----------------------------------------------------------------------
      resources :enrollment_certifications, only: %i[create show] do
        # Nested status polling endpoint for the confirmation page
        # GET  /v0/education/enrollment_certifications/:id/status
        member do
          get :status
        end
      end

      # -----------------------------------------------------------------------
      # Institution lookup — facility code validation + auto-populate
      # GET /v0/education/institution?facility_code=XXXXXXXX
      # -----------------------------------------------------------------------
      get  :institution,        to: 'institutions#show',       as: :institution_lookup

      # -----------------------------------------------------------------------
      # COE / eligibility check
      # POST /v0/education/coe_check
      # Body: { ssn, va_file_number, date_of_birth, gi_chapter }
      # -----------------------------------------------------------------------
      post :coe_check,          to: 'coe_checks#create',       as: :coe_check

      # -----------------------------------------------------------------------
      # Yellow Ribbon Agreement lookup
      # GET /v0/education/yellow_ribbon_agreement?facility_code=XXXXXXXX&academic_year=2024-2025
      # -----------------------------------------------------------------------
      get  :yellow_ribbon_agreement, to: 'yellow_ribbon_agreements#show', as: :yellow_ribbon_agreement
    end
  end
end