# spec/controllers/v0/education/enrollment_certifications_controller_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Education::EnrollmentCertificationsController, type: :controller do
  let(:user) { create(:user, :loa3) }

  # ---------------------------------------------------------------------------
  # Shared fixture data
  # ---------------------------------------------------------------------------

  let(:valid_form_data) do
    {
      'scoVerification' => {
        'scoName'     => 'Jane Smith',
        'facilityCode' => '12345678',
        'scoRole'     => 'primary_certifying_official'
      },
      'certificationTypeInfo' => {
        'certificationType' => 'original'
      },
      'studentInformation' => {
        'firstName'   => 'John',
        'lastName'    => 'Doe',
        'ssn'         => '123456789',
        'dateOfBirth' => '1995-06-15',
        'giChapter'   => '33'
      },
      'institutionInformation' => {
        'facilityCode'     => '12345678',
        'institutionName'  => 'State University',
        'institutionType'  => 'IHL',
        'publicOrPrivate'  => 'public',
        'institutionState' => 'VA',
        'studentState'     => 'VA'
      },
      'programInformation' => {
        'programName' => 'Computer Science',
        'degreeLevel' => 'bachelors'
      },
      'enrollmentPeriod' => {
        'enrollmentBeginDate' => Date.today.strftime('%Y-%m-%d'),
        'enrollmentEndDate'   => (Date.today + 120.days).strftime('%Y-%m-%d'),
        'termType'            => 'semester'
      },
      'creditHours' => {
        'hoursEnrolled'              => 12,
        'institutionFullTimeHours'   => 12,
        'trainingTimeClassification' => 'full_time'
      },
      'certifyingOfficial' => {
        'officialName'       => 'Jane Smith',
        'officialTitle'      => 'School Certifying Official',
        'officialPhone'      => '5555550100',
        'officialEmail'      => 'jane.smith@stateuniversity.edu',
        'attestationSigned'  => true
      }
    }
  end

  # ---------------------------------------------------------------------------
  # POST #create
  # ---------------------------------------------------------------------------

  describe 'POST #create' do
    context 'when authenticated as LOA3 user' do
      before { sign_in_as(user) }

      context 'with valid form data' do
        before do
          allow(Lighthouse::Submit221999Job).to receive(:perform_async).and_return('fake-jid-001')
        end

        it 'returns HTTP 201 Created' do
          post :create, params: { form_data: valid_form_data }, format: :json
          expect(response).to have_http_status(:created)
        end

        it 'creates an EnrollmentCertification record' do
          expect {
            post :create, params: { form_data: valid_form_data }, format: :json
          }.to change(EnrollmentCertification, :count).by(1)
        end

        it 'enqueues a Lighthouse submission job' do
          expect(Lighthouse::Submit221999Job).to receive(:perform_async)
          post :create, params: { form_data: valid_form_data }, format: :json
        end

        it 'returns JSONAPI-formatted body with status pending' do
          post :create, params: { form_data: valid_form_data }, format: :json
          json = JSON.parse(response.body)
          expect(json['data']).to be_present
          expect(json['data']['attributes']['status']).to eq('pending')
        end

        it 'sets user_uuid on the new record' do
          post :create, params: { form_data: valid_form_data }, format: :json
          record = EnrollmentCertification.last
          expect(record.user_uuid).to eq(user.uuid)
        end

        it 'strips submissionMetadata from persisted form_data' do
          data_with_meta = valid_form_data.merge(
            'submissionMetadata' => { 'submittedAt' => '2025-01-10T00:00:00Z' }
          )
          post :create, params: { form_data: data_with_meta }, format: :json
          record = EnrollmentCertification.last
          expect(record.form_data).not_to have_key('submissionMetadata')
        end

        it 'increments StatsD submission_enqueued counter' do
          expect(StatsD).to receive(:increment).with(
            'api.v0.education.enrollment_certifications.submission_enqueued'
          )
          allow(Lighthouse::Submit221999Job).to receive(:perform_async)
          post :create, params: { form_data: valid_form_data }, format: :json
        end
      end

      context 'with missing required sections' do
        it 'returns HTTP 422 Unprocessable Entity' do
          post :create, params: { form_data: { 'scoVerification' => {} } }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns error details in the response' do
          post :create, params: { form_data: { 'scoVerification' => {} } }, format: :json
          json = JSON.parse(response.body)
          expect(json['errors']).to be_an(Array)
          expect(json['errors'].first['title']).to eq('Validation Error')
        end

        it 'does not enqueue a job' do
          expect(Lighthouse::Submit221999Job).not_to receive(:perform_async)
          post :create, params: { form_data: { 'scoVerification' => {} } }, format: :json
        end

        it 'does not create a record' do
          expect {
            post :create, params: { form_data: { 'scoVerification' => {} } }, format: :json
          }.not_to change(EnrollmentCertification, :count)
        end

        it 'increments StatsD validation_failure counter' do
          expect(StatsD).to receive(:increment).with(
            'api.v0.education.enrollment_certifications.validation_failure'
          )
          post :create, params: { form_data: { 'scoVerification' => {} } }, format: :json
        end
      end

      context 'with invalid facility code format' do
        it 'returns 422 and a descriptive facility code error' do
          bad_data = valid_form_data.deep_dup
          bad_data['scoVerification']['facilityCode'] = '123'
          post :create, params: { form_data: bad_data }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          errors_detail = JSON.parse(response.body)['errors'].map { |e| e['detail'] }.join
          expect(errors_detail).to include('8 digits')
        end
      end

      context 'with invalid SSN format' do
        it 'returns 422 with SSN validation error' do
          bad_data = valid_form_data.deep_dup
          bad_data['studentInformation']['ssn'] = '000123456'
          post :create, params: { form_data: bad_data }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          errors_detail = JSON.parse(response.body)['errors'].map { |e| e['detail'] }.join
          expect(errors_detail).to match(/ssn/)
        end
      end

      context 'with enrollment end date before begin date' do
        it 'returns 422 with date ordering error' do
          bad_data = valid_form_data.deep_dup
          bad_data['enrollmentPeriod']['enrollmentEndDate'] = '2020-01-01'
          post :create, params: { form_data: bad_data }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          errors_detail = JSON.parse(response.body)['errors'].map { |e| e['detail'] }.join
          expect(errors_detail).to include('enrollmentEndDate must be after enrollmentBeginDate')
        end
      end

      context 'with attestationSigned set to false' do
        it 'returns 422 with attestation error' do
          bad_data = valid_form_data.deep_dup
          bad_data['certifyingOfficial']['attestationSigned'] = false
          post :create, params: { form_data: bad_data }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          errors_detail = JSON.parse(response.body)['errors'].map { |e| e['detail'] }.join
          expect(errors_detail).to include('attestationSigned must be true')
        end
      end

      context 'with classificationOverridden true but no justification' do
        it 'returns 422 with override justification error' do
          bad_data = valid_form_data.deep_dup
          bad_data['creditHours']['classificationOverridden'] = true
          bad_data['creditHours'].delete('overrideJustification')
          post :create, params: { form_data: bad_data }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          errors_detail = JSON.parse(response.body)['errors'].map { |e| e['detail'] }.join
          expect(errors_detail).to include('overrideJustification is required')
        end
      end
    end

    context 'when unauthenticated' do
      it 'returns HTTP 401 Unauthorized' do
        post :create, params: { form_data: valid_form_data }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not create a record' do
        expect {
          post :create, params: { form_data: valid_form_data }, format: :json
        }.not_to change(EnrollmentCertification, :count)
      end
    end

    context 'when authenticated as LOA1 user (identity not verified)' do
      let(:loa1_user) { create(:user, :loa1) }

      before { sign_in_as(loa1_user) }

      it 'returns HTTP 403 Forbidden' do
        post :create, params: { form_data: valid_form_data }, format: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns a LOA3 required error message' do
        post :create, params: { form_data: valid_form_data }, format: :json
        json = JSON.parse(response.body)
        expect(json['errors'].first['detail']).to include('LOA3')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET #show
  # ---------------------------------------------------------------------------

  describe 'GET #show' do
    let!(:submission) do
      create(:enrollment_certification,
             user_uuid: user.uuid,
             status:    :success,
             confirmation_number: 'ABC-123-DEF')
    end

    context 'when authenticated as LOA3 user who owns the record' do
      before { sign_in_as(user) }

      it 'returns HTTP 200 OK' do
        get :show, params: { id: submission.id }, format: :json
        expect(response).to have_http_status(:ok)
      end

      it 'returns the confirmation number' do
        get :show, params: { id: submission.id }, format: :json
        json = JSON.parse(response.body)
        expect(json['data']['attributes']['confirmation_number']).to eq('ABC-123-DEF')
      end

      it 'returns the correct status' do
        get :show, params: { id: submission.id }, format: :json
        json = JSON.parse(response.body)
        expect(json['data']['attributes']['status']).to eq('success')
      end
    end

    context 'when authenticated as a different user' do
      let(:other_user) { create(:user, :loa3) }

      before { sign_in_as(other_user) }

      it 'returns HTTP 404 Not Found' do
        get :show, params: { id: submission.id }, format: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when unauthenticated' do
      it 'returns HTTP 401 Unauthorized' do
        get :show, params: { id: submission.id }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end