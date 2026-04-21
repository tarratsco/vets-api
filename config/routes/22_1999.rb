# config/routes/22_1999.rb
# frozen_string_literal: true

# This file is drawn from config/routes.rb via:
#   draw :enrollment_certifications_22_1999
# or inlined into the v0 namespace block.

Rails.application.routes.draw do
  namespace :v0, defaults: { format: :json } do
    namespace :education do
      resources :enrollment_certifications,
                only:       %i[create show],
                controller: 'enrollment_certifications' do
        collection do
          # Optional: allow SCO to check recent submissions
          get :status
        end
      end
    end
  end
end