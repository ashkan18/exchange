require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'confirm_pickup mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:credit_card_id) { 'cc-1' }
    let(:order) { Fabricate(:order, seller_id: seller_id, buyer_id: user_id, fulfillment_type: Order::PICKUP) }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: ConfirmPickupInput!) {
          confirmPickup(input: $input) {
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

    let(:confirm_pickup_input) do
      {
        input: {
          id: order.id.to_s
        }
      }
    end

    context 'with user without permission to this partner' do
      let(:seller_id) { 'another-partner-id' }
      it 'returns permission error' do
        response = client.execute(mutation, confirm_pickup_input)
        expect(response.data.confirm_pickup.order_or_error.error.type).to eq 'validation'
        expect(response.data.confirm_pickup.order_or_error.error.code).to eq 'not_found'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with proper permission' do
      Order::STATES.reject { |s| [Order::APPROVED, Order::CANCELED].include? s }.each do |state|
        context "with order not in #{state} state" do
          before do
            order.update! state: state
          end
          it 'returns error' do
            response = client.execute(mutation, confirm_pickup_input)
            expect(response.data.confirm_pickup.order_or_error.error.type).to eq 'validation'
            expect(response.data.confirm_pickup.order_or_error.error.code).to eq 'invalid_state'
            expect(order.reload.state).to eq state
          end
        end
      end

      context 'order in approved state' do
        before do
          order.update! state: Order::APPROVED
        end
        context 'shipping order' do
          before do
            order.update! fulfillment_type: Order::SHIP
          end
          it 'returns error' do
            response = client.execute(mutation, confirm_pickup_input)
            expect(response.data.confirm_pickup.order_or_error.error.type).to eq 'validation'
            expect(response.data.confirm_pickup.order_or_error.error.code).to eq 'wrong_fulfillment_type'
            expect(order.reload.state).to eq Order::APPROVED
          end
        end

        context 'pickup order' do
          it 'approves the order' do
            response = client.execute(mutation, confirm_pickup_input)
            expect(response.data.confirm_pickup.order_or_error.order.id).to eq order.id.to_s
            expect(response.data.confirm_pickup.order_or_error.order.state).to eq 'FULFILLED'
            expect(response.data.confirm_pickup.order_or_error).not_to respond_to(:error)
            expect(order.reload.state).to eq Order::FULFILLED
            expect(order.state_expires_at).to be_nil
          end

          it 'queues a job for posting events' do
            client.execute(mutation, confirm_pickup_input)
            expect(PostOrderNotificationJob).to have_been_enqueued
          end
        end
      end
    end
  end
end
