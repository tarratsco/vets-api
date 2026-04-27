# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Formva401330mController, type: :controller do
  let(:valid_form_data) do
    {
      serviceStatusAtDeath:     'activeDuty',
      submitterRole:            'nextOfKin',
      certificationAttestation: true,
      applicant: {
        name:         { first: 'Jane', last: 'Doe' },
        daytimePhone: '5551234567',
        email:        'jane.doe@example.com',
        address: {
          street:     '123 Main St',
          city:       'Arlington',
          state:      'VA',
          postalCode: '22201',
          country:    'USA'
        }
      },
      decedent: {
        name:        { first: 'John', last: 'Doe' },
        ssn:         '123456789',
        dateOfBirth: '1985-06-15',
        dateOfDeath: '2024-01-10',
        placeOfDeath: { city: 'Washington', state: 'DC', country: 'USA' },
        service: {
          branchOfService:  'army',
          component:        'active',
          rankAtDeath:      'Sergeant',
          serviceEntryDate: '2005-06-01'
        }
      },
      burialLocation: {
        cemeteryName:         'Arlington National Cemetery',
        cemeteryContactName:  'John Smith',
        cemeteryContactPhone: '7035551234',
        existingMarkerPresent: 'noExistingMarker',
        cemeteryAddress: {
          street:     '1 Memorial Ave',
          city:       'Arlington',
          state:      'VA',
          postalCode: '22211',
          country:    'USA'
        }
      },
      markerRequest: { markerType: 'uprightGranite' },
      documents: {
        deathCertificate: { name: 'cert.pdf', confirmationCode: 'abc-uuid' },
        ddForm1300:       { name: 'dd1300.pdf', confirmationCode: 'def-uuid' }
      }
    }
  end

  # Wrap form data under the expected param key
  let(:valid_params) { { formva40_1330m: valid_form_data } }

  # ---------------------------------------------------------------------------
  # Unauthenticated requests
  # ---------------------------------------------------------------------------
  describe 'POST #create — unauthenticated' do
    it 'returns 401' do
      post :create, params: valid_params
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ---------------------------------------------------------------------------
  # Authenticated LOA3 requests
  # ---------------------------------------------------------------------------
  describe 'POST #create — authenticated LOA3' do
    let(:loa3_user) { build(:user, :loa3) }

    before do
      sign_in_as_user(loa3_user)
      allow(Lighthouse::SubmitFormva401330mJob).to receive(:perform_async)
    end

    context 'with valid params' do
      it 'returns HTTP 200' do
        post :create, params: valid_params
        expect(response).to have_http_status(:ok)
      end

      it 'creates a Formva401330mSubmission record' do
        expect {
          post :create, params: valid_params
        }.to change(Formva401330mSubmission, :count).by(1)
      end

      it 'enqueues a Lighthouse submission job' do
        post :create, params: valid_params
        expect(Lighthouse::SubmitFormva401330mJob).to have_received(:perform_async)
      end

      it 'returns JSON with status key' do
        post :create, params: valid_params
        body = JSON.parse(response.body)
        expect(body).to have_key('status').or have_key('data')
      end

      it 'increments the enqueued StatsD counter' do
        expect(StatsD).to receive(:increment).with('api.burial_forms.va40_1330m.submission.enqueued')
        allow(StatsD).to receive(:increment) # allow other calls
        post :create, params: valid_params
      end
    end

    context 'with missing required params (empty body)' do
      it 'returns HTTP 422' do
        post :create, params: { formva40_1330m: {} }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns a JSON errors array' do
        post :create, params: { formva40_1330m: {} }
        body = JSON.parse(response.body)
        expect(body['errors']).to be_an(Array)
        expect(body['errors']).not_to be_empty
      end

      it 'does not enqueue a Sidekiq job' do
        post :create, params: { formva40_1330m: {} }
        expect(Lighthouse::SubmitFormva401330mJob).not_to have_received(:perform_async)
      end
    end

    context 'with missing root param key' do
      it 'returns HTTP 400 (ActionController::ParameterMissing)' do
        post :create, params: {}
        expect(response.status).to be_in([400, 422])
      end
    end

    context 'with invalid certificationAttestation (false)' do
      let(:bad_params) do
        valid_params.deep_merge(formva40_1330m: { certificationAttestation: false })
      end

      it 'returns 422' do
        post :create, params: bad_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with activeDuty status but missing DD Form 1300' do
      let(:no_dd1300_params) do
        data = valid_form_data.deep_dup
        data[:documents].delete(:ddForm1300)
        { formva40_1330m: data }
      end

      it 'returns 422 with relevant error message' do
        post :create, params: no_dd1300_params
        body = JSON.parse(response.body)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['errors'].join).to match(/ddForm1300|DD Form 1300/i)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Authenticated LOA1 requests (identity not verified)
  # ---------------------------------------------------------------------------
  describe 'POST #create — authenticated LOA1 (insufficient identity level)' do
    let(:loa1_user) { build(:user, :loa1) }

    before { sign_in_as_user(loa1_user) }

    it 'returns HTTP 403' do
      post :create, params: valid_params
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns an LOA3 required error message' do
      post :create, params: valid_params
      body = JSON.parse(response.body)
      expect(body['errors'].join).to match(/LOA3/i)
    end
  end
end