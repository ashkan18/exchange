require 'rails_helper'
require 'support/use_stripe_mock'

describe Api::GraphqlController, type: :request do
  include_context 'use stripe mock'

  describe 'approve_order mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:credit_card_id) { 'cc-1' }
    let(:order) { Fabricate(:order, seller_id: seller_id, buyer_id: user_id) }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: ApproveOrderInput!) {
          approveOrder(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  buyer {
                    ... on Partner {
                      id
                    }
                  }
                  seller {
                    ... on User {
                      id
                    }
                  }
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    let(:approve_order_input) do
      {
        input: {
          id: order.id.to_s
        }
      }
    end

    context 'with user without permission to this partner' do
      let(:seller_id) { 'another-partner-id' }
      it 'returns permission error' do
        response = client.execute(mutation, approve_order_input)
        expect(response.data.approve_order.order_or_error.error.type).to eq 'validation'
        expect(response.data.approve_order.order_or_error.error.code).to eq 'not_found'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with order not in submitted state' do
      before do
        order.update_attributes! state: Order::PENDING
      end
      it 'returns error' do
        response = client.execute(mutation, approve_order_input)
        expect(response.data.approve_order.order_or_error.error.type).to eq 'validation'
        expect(response.data.approve_order.order_or_error.error.code).to eq 'invalid_state'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with proper permission' do
      before do
        order.update_attributes! state: Order::SUBMITTED
        order.update_attributes! external_charge_id: uncaptured_charge.id
      end
      it 'approves the order' do
        expect do
          response = client.execute(mutation, approve_order_input)
          expect(response.data.approve_order.order_or_error.order.id).to eq order.id.to_s
          expect(response.data.approve_order.order_or_error.order.state).to eq 'APPROVED'
          expect(response.data.approve_order.order_or_error).not_to respond_to(:error)
          expect(order.reload.state).to eq Order::APPROVED
          expect(order.reload.transactions.last.external_id).to eq uncaptured_charge.id
          expect(order.reload.transactions.last.transaction_type).to eq Transaction::CAPTURE
        end.to change(order, :state_expires_at)
      end

      it 'queues a job for posting events' do
        client.execute(mutation, approve_order_input)
        expect(PostOrderNotificationJob).to have_been_enqueued
      end

      it 'queues a job for rejecting the order when the order should expire' do
        client.execute(mutation, approve_order_input)
        job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
        expect(job).to_not be_nil
        expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
        expect(job[:args][0]).to eq order.id
        expect(job[:args][1]).to eq Order::APPROVED
      end
    end
  end
end
