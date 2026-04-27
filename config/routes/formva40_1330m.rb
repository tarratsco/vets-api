# frozen_string_literal: true

# Route fragment for VA Form 40-1330M (Headstone or Marker Request).
# This file is loaded by config/routes.rb via:
#   instance_eval(File.read(Rails.root.join('config/routes/formva40_1330m.rb')))
# or alternatively drawn inside the main routes.rb `draw :formva40_1330m` call.
Rails.application.routes.draw do
  namespace :v0 do
    post 'formva40_1330m', to: 'formva40_1330m#create'
  end
end