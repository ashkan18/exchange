require 'rails_helper'

describe Api::GraphqlController, type: :request do
  include_context 'use stripe mock'

  describe 'reject_order mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:credit_card_id) { 'cc-1' }
    let(:order) { Fabricate(:order, seller_id: seller_id, buyer_id: user_id, external_charge_id: captured_charge.id) }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: RejectOrderInput!) {
          rejectOrder(input: $input) {
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

    let(:reject_order_input) do
      {
        input: {
          id: order.id.to_s
        }
      }
    end
    context 'with user without permission to this partner' do
      let(:seller_id) { 'another-partner-id' }
      it 'returns permission error' do
        response = client.execute(mutation, reject_order_input)
        expect(response.data.reject_order.order_or_error.error.type).to eq 'validation'
        expect(response.data.reject_order.order_or_error.error.code).to eq 'not_found'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with order not in submitted state' do
      before do
        order.update_attributes! state: Order::PENDING
      end
      it 'returns error' do
        response = client.execute(mutation, reject_order_input)
        expect(response.data.reject_order.order_or_error.error.type).to eq 'validation'
        expect(response.data.reject_order.order_or_error.error.code).to eq 'invalid_state'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with proper permission' do
      before do
        order.update_attributes! state: Order::SUBMITTED
      end
      it 'rejects the order' do
        response = client.execute(mutation, reject_order_input)
        expect(response.data.reject_order.order_or_error.order.id).to eq order.id.to_s
        expect(response.data.reject_order.order_or_error.order.state).to eq 'CANCELED'
        expect(response.data.reject_order.order_or_error).not_to respond_to(:error)
        expect(order.reload.state).to eq Order::CANCELED
        expect(order.transactions.last.external_id).to_not eq nil
        expect(order.transactions.last.transaction_type).to eq Transaction::REFUND
      end
    end
  end
end
