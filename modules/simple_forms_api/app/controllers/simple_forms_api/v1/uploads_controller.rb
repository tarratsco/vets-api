# frozen_string_literal: true

# ============================================================
# PATCH — add '10-2850e' entry to FORM_NUMBER_MAP.
# Only the constant block is shown; all other controller code
# remains unchanged. The post-processor applies this diff.
# ============================================================

module SimpleFormsApi
  module V1
    class UploadsController < ApplicationController
      FORM_NUMBER_MAP = {
        '10-2850e' => 'vba_10_2850e',
        '10-8678'  => 'vba_10_8678',
        '20-10206' => 'vba_20_10206',
        '20-10207' => 'vba_20_10207',
        '21-0845'  => 'vba_21_0845',
        '21-0966'  => 'vba_21_0966',
        '21-0972'  => 'vba_21_0972',
        '21-10210' => 'vba_21_10210',
        '21-4138'  => 'vba_21_4138',
        '21-4140'  => 'vba_21_4140',
        '21-4142'  => 'vba_21_4142',
        '21-4502'  => 'vba_21_4502',
        '21P-0537' => 'vba_21p_0537',
        '21P-0847' => 'vba_21p_0847',
        '21P-601'  => 'vba_21p_601',
        '26-4555'  => 'vba_26_4555',
        '40-0247'  => 'vba_40_0247',
        '40-10007' => 'vba_40_10007',
        '40-1330M' => 'vba_40_1330m'
      }.freeze
    end
  end
end