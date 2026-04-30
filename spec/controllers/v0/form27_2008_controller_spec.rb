# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Form27_2008Controller, type: :controller do
  let(:loa3_user) { build(:user, :loa3) }

  let(:valid_form_params) do
    {
      burialFlagApplication: {
        applicantType: 'nextOfKin',
        dateSigned: '2024-01-15',
        certificationChecked: true,
        veteranInformation: {
          firstName: 'John',
          lastName: 'Veteran',
          dateOfBirth: '1945-06-15',
          dateOfDeath: '2024-01-10',
          dateOfBurial: '2024-01-17',
          placeOfBurialCemeteryName: 'Arlington National Cemetery',
          placeOfBurialCity: 'Arlington',
          placeOfBurialState: 'VA'
        },
        serviceInformation: {
          branchOfService: ['army'],
          dateEnteredActiveDuty: '1965-03-01',
          dateReleasedFromActiveDuty: '1968-02-28'
        },
        eligibility: {
          documentationAvailable: true,
          dischargeCharacter: 'honorable'
        },
        flagRecipient: {
          recipientFullName: 'Jane Veteran',
          recipientRelationship: 'survivingSpouse',
          recipientAddressLine1: '123 Main St',
          recipientCity: 'Springfield',
          recipientState: 'VA',
          recipientZip: '22001'
        },
        applicant: {
          firstName: 'Jane',
          lastName: 'Veteran',
          addressLine1: '123 Main St',
          city: 'Springfield',
          state: 'VA',
          zip: '22001',
          relationshipToVeteran: 'survivingSpouse'
        }
      }
    }
  end

  before do
    allow(Lighthouse::SubmitForm27_2008Job).to receive(:perform_async)
    allow(StatsD).to receive(:increment)
  end

  describe '#create' do
    context 'when authenticated as LOA3 user' do
      before { sign_in_as_user(loa3_user) }

      context 'with valid params' do
        it 'returns HTTP 200' do
          post :create, params: valid_form_params
          expect(response).to have_http_status(:ok)
        end

        it 'creates a Form27_2008Submission record' do
          expect do
            post :create, params: valid_form_params
          end.to change(Form27_2008Submission, :count).by(1)
        end

        it 'enqueues a Lighthouse submission job' do
          post :create, params: valid_form_params
          expect(Lighthouse::SubmitForm27_2008Job).to have_received(:perform_async)
        end

        it 'returns serialized submission with expected keys' do
          post :create, params: valid_form_params
          json = JSON.parse(response.body)
          expect(json['data']['attributes']).to include('status', 'confirmation_number', 'submitted_at')
        end

        it 'emits a StatsD success metric' do
          post :create, params: valid_form_params
          expect(StatsD).to have_received(:increment)
            .with("api.form27_2008.submission.success", anything)
        end

        it 'stores the user_uuid on the submission' do
          post :create, params: valid_form_params
          submission = Form27_2008Submission.last
          expect(submission.user_uuid).to eq(loa3_user.uuid)
        end
      end

      context 'with missing required params' do
        it 'returns HTTP 422 when burialFlagApplication key is absent' do
          post :create, params: {}
          # Expecting either 422 or 400 — ActionController::ParameterMissing
          # raises a Bad Request by default in Rails, so we allow both
          expect(response.status).to be_in([400, 422])
        end

        it 'returns HTTP 422 when certificationChecked is false' do
          params = valid_form_params.deep_dup
          params[:burialFlagApplication][:certificationChecked] = false
          post :create, params: params
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns error messages in response body' do
          params = valid_form_params.deep_dup
          params[:burialFlagApplication][:certificationChecked] = false
          post :create, params: params
          json = JSON.parse(response.body)
          expect(json['errors']).to be_a(Array)
          expect(json['errors']).not_to be_empty
        end

        it 'does not enqueue a job on validation failure' do
          params = valid_form_params.deep_dup
          params[:burialFlagApplication][:certificationChecked] = false
          post :create, params: params
          expect(Lighthouse::SubmitForm27_2008Job).not_to have_received(:perform_async)
        end

        it 'returns HTTP 422 when veteran information is incomplete' do
          params = valid_form_params.deep_dup
          params[:burialFlagApplication][:veteranInformation].delete(:firstName)
          post :create, params: params
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when authenticated as LOA1 (not LOA3)' do
        let(:loa1_user) { build(:user, :loa1) }

        before { sign_in_as_user(loa1_user) }

        it 'returns HTTP 403 forbidden' do
          post :create, params: valid_form_params
          expect(response).to have_http_status(:forbidden)
        end

        it 'does not create a submission record' do
          expect do
            post :create, params: valid_form_params
          end.not_to change(Form27_2008Submission, :count)
        end
      end
    end

    context 'when unauthenticated' do
      it 'returns HTTP 401 unauthorized' do
        post :create, params: valid_form_params
        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not create a submission record' do
        expect do
          post :create, params: valid_form_params
        end.not_to change(Form27_2008Submission, :count)
      end

      it 'does not enqueue a job' do
        post :create, params: valid_form_params
        expect(Lighthouse::SubmitForm27_2008Job).not_to have_received(:perform_async)
      end
    end
  end
end