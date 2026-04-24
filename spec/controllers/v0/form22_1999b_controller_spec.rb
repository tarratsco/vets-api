# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Form22_1999bController, type: :controller do
  let(:valid_params) do
    {
      form22_1999b: {
        institutionAndScoInformation: {
          facilityCode:    '31000123',
          institutionName: 'State University of Example',
          institutionAddress: {
            street: '123 University Ave',
            city:   'Richmond',
            state:  'VA',
            zip:    '23220'
          },
          scoFirstName: 'Maria',
          scoLastName:  'Hernandez',
          scoTitle:     'Associate Registrar',
          scoPhone:     '5558675309',
          scoEmail:     'certifying.official@university.edu'
        },
        studentAndPriorCertification: {
          studentFirstName:         'James',
          studentLastName:          'Nguyen',
          ssnOrFileNumberIndicator: 'ssn',
          studentSsn:               '123456789',
          benefitChapter:           'chapter_33',
          originalCertBeginDate:    '2024-08-19',
          originalCertEndDate:      '2024-12-15',
          originalCreditHours:      12,
          originalEnrollmentType:   'full_time'
        },
        enrollmentChangeDetails: {
          typeOfChange:          'full_termination',
          effectiveDateOfChange: 10.days.ago.to_date.iso8601,
          lastDateOfAttendance:  11.days.ago.to_date.iso8601,
          reasonForChange:       'medical'
        },
        scoCertificationAttested: true
      }
    }
  end

  describe '#create' do
    context 'when authenticated at LOA2' do
      before { sign_in_as_user }

      context 'with valid params' do
        before do
          allow(Lighthouse::SubmitForm22_1999bJob).to receive(:perform_async)
        end

        it 'returns HTTP 201 Created' do
          post :create, params: valid_params
          expect(response).to have_http_status(:created)
        end

        it 'enqueues a Lighthouse submission job' do
          expect(Lighthouse::SubmitForm22_1999bJob).to receive(:perform_async).once
          post :create, params: valid_params
        end

        it 'returns a JSON body with status, confirmation_number, and submitted_at keys' do
          post :create, params: valid_params
          json = JSON.parse(response.body)
          expect(json).to have_key('status')
          expect(json).to have_key('confirmation_number')
          expect(json).to have_key('submitted_at')
        end

        it 'persists a Form22_1999bSubmission record' do
          expect {
            post :create, params: valid_params
          }.to change(Form22_1999bSubmission, :count).by(1)
        end
      end

      context 'with missing form wrapper key' do
        it 'returns HTTP 422' do
          post :create, params: {}
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when attestation is false' do
        let(:params_without_attestation) do
          valid_params.deep_merge(form22_1999b: { scoCertificationAttested: false })
        end

        it 'returns HTTP 422' do
          post :create, params: params_without_attestation
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns an error message about attestation' do
          post :create, params: params_without_attestation
          json = JSON.parse(response.body)
          expect(json['errors'].join).to match(/attestation/i)
        end
      end

      context 'when SSN indicator is ssn but studentSsn is missing' do
        let(:params_no_ssn) do
          p = valid_params.deep_merge(
            form22_1999b: {
              studentAndPriorCertification: { studentSsn: nil }
            }
          )
          p
        end

        it 'returns HTTP 422' do
          post :create, params: params_no_ssn
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when effective date is in the future' do
        let(:params_future_date) do
          valid_params.deep_merge(
            form22_1999b: {
              enrollmentChangeDetails: { effectiveDateOfChange: 5.days.from_now.to_date.iso8601 }
            }
          )
        end

        it 'returns HTTP 422' do
          post :create, params: params_future_date
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns an error message about the future date' do
          post :create, params: params_future_date
          json = JSON.parse(response.body)
          expect(json['errors'].join).to match(/future/i)
        end
      end

      context 'when typeOfChange is full_termination and lastDateOfAttendance is missing' do
        let(:params_no_last_attend) do
          valid_params.deep_merge(
            form22_1999b: {
              enrollmentChangeDetails: { lastDateOfAttendance: nil }
            }
          )
        end

        it 'returns HTTP 422' do
          post :create, params: params_no_last_attend
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when typeOfChange is correction and correctionItems is empty' do
        let(:params_correction_no_items) do
          valid_params.deep_merge(
            form22_1999b: {
              enrollmentChangeDetails: {
                typeOfChange:     'correction',
                reasonForChange:  nil,
                correctionDetails: { correctionItems: [] }
              }
            }
          )
        end

        it 'returns HTTP 422' do
          post :create, params: params_correction_no_items
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when submission is late and lateSubmissionExplanation is missing' do
        let(:params_late_no_explanation) do
          valid_params.deep_merge(
            form22_1999b: {
              enrollmentChangeDetails: {
                effectiveDateOfChange:  45.days.ago.to_date.iso8601,
                lastDateOfAttendance:   46.days.ago.to_date.iso8601,
                lateSubmissionExplanation: nil
              }
            }
          )
        end

        it 'returns HTTP 422' do
          post :create, params: params_late_no_explanation
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns an error message about late submission explanation' do
          post :create, params: params_late_no_explanation
          json = JSON.parse(response.body)
          expect(json['errors'].join).to match(/explanation/i)
        end
      end

      context 'when mitigating circumstances are known but narrative is blank' do
        let(:params_missing_narrative) do
          valid_params.deep_merge(
            form22_1999b: {
              enrollmentChangeDetails: {
                reasonForChange: 'medical',
                mitigatingCircumstances: {
                  mitigatingCircumstancesKnown:     'yes',
                  mitigatingCircumstancesNarrative: ''
                }
              }
            }
          )
        end

        it 'returns HTTP 422' do
          post :create, params: params_missing_narrative
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when authenticated at LOA1 (insufficient)' do
      before { sign_in_as_user(loa: { current: 1, highest: 1 }) }

      it 'returns HTTP 403 Forbidden' do
        post :create, params: valid_params
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'returns HTTP 401 Unauthorized' do
        post :create, params: valid_params
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end