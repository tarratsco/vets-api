# frozen_string_literal: true

# VA Form 22-1999b — Enrollment Change / Termination Certification
# These routes are drawn into the main vets-api route set via the
# draw(:form22_1999b) call in config/routes.rb.
#
# To register:  add `draw(:form22_1999b)` inside the `namespace :v0` block
# in the root config/routes.rb.

namespace :v0, defaults: { format: :json } do
  post 'form22_1999b', to: 'form22_1999b#create'
end