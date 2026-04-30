# frozen_string_literal: true

# VA Form 27-2008 — Application for United States Flag for Burial Purposes
# Routes fragment loaded by the main config/routes.rb via draw(:form27_2008).
#
# Note: The canonical submission path for unauthenticated users flows through
# the simple_forms_api module endpoint:
#   POST /simple_forms_api/v1/simple_forms
# This route provides the authenticated LOA3 endpoint:
#   POST /v0/form27_2008
#
# To wire this file into the main routes, add to config/routes.rb:
#   draw :form27_2008

namespace :v0 do
  post 'form27_2008', to: 'form27_2008#create'
end