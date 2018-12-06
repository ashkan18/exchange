require 'rails_helper'

def ids_from_result_data(result)
  result.data.orders.edges.map(&:node).map(&:id)
end

describe Api::GraphqlController, type: :request do
  describe 'orders query' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:second_seller_id) { 'partner-2' }
    let(:user_id) { jwt_user_id }
    let(:second_user) { 'user2' }
    let!(:user1_order1) { Fabricate(:order, seller_type: 'partner', seller_id: seller_id, buyer_type: 'user', buyer_id: user_id, updated_at: 3.days.ago) }
    let!(:user1_order2) { Fabricate(:order, seller_type: 'partner', seller_id: second_seller_id, buyer_type: 'user', buyer_id: user_id, updated_at: 2.days.ago) }
    let!(:user1_offer_order1) { Fabricate(:order, seller_type: 'partner', seller_id: second_seller_id, buyer_type: 'user', buyer_id: user_id, updated_at: 1.day.ago, mode: Order::OFFER) }
    let!(:user2_order1) { Fabricate(:order, seller_type: 'partner', seller_id: seller_id, buyer_type: 'user', buyer_id: second_user) }

    let(:query) do
      <<-GRAPHQL
        query($sellerId: String, $buyerId: String, $state: OrderStateEnum, $sort: OrderConnectionSortEnum, $mode: OrderModeEnum) {
          orders(sellerId: $sellerId, buyerId: $buyerId, state: $state, sort: $sort, mode: $mode) {
            edges {
              node {
                id
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
                state
                currencyCode
                itemsTotalCents
                lineItems{
                  edges{
                    node{
                      priceCents
                    }
                  }
                }
                requestedFulfillment{
                  ... on Ship {
                    name
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns error when missing both buyerId and sellerId' do
      expect do
        client.execute(query, state: 'PENDING')
      end.to raise_error do |error|
        expect(error).to be_a(Graphlient::Errors::ServerError)
        expect(error.message).to eq 'the server responded with status 400'
        expect(error.status_code).to eq 400
        expect(error.response['errors'].first['extensions']['code']).to eq 'missing_params'
        expect(error.response['errors'].first['extensions']['type']).to eq 'validation'
      end
    end

    context 'query with sellerId' do
      it 'returns not found error when query for sellerId not in jwt' do
        expect do
          client.execute(query, sellerId: 'someone-elses-partnerid')
        end.to raise_error do |error|
          expect(error).to be_a(Graphlient::Errors::ServerError)
          expect(error.message).to eq 'the server responded with status 404'
          expect(error.status_code).to eq 404
          expect(error.response['errors'].first['extensions']['code']).to eq 'not_found'
          expect(error.response['errors'].first['extensions']['type']).to eq 'validation'
        end
      end
      it 'returns partners orders' do
        result = client.execute(query, sellerId: seller_id)
        expect(result.data.orders.edges.count).to eq 2
        ids = ids_from_result_data(result)
        expect(ids).to match_array([user1_order1.id, user2_order1.id])
      end
    end

    context 'query with buyerId' do
      it 'returns buyers orders' do
        result = client.execute(query, buyerId: user_id)
        expect(result.data.orders.edges.count).to eq 3
        ids = ids_from_result_data(result)
        expect(ids).to match_array([user1_order1.id, user1_order2.id, user1_offer_order1.id])
      end

      it 'sorts by updated_at in ascending order' do
        result = client.execute(query, buyerId: user_id, sort: 'UPDATED_AT_ASC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_order1.id, user1_order2.id, user1_offer_order1.id])
      end

      it 'sorts by updated_at in descending order' do
        result = client.execute(query, buyerId: user_id, sort: 'UPDATED_AT_DESC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_offer_order1.id, user1_order2.id, user1_order1.id])
      end

      it 'sorts by state_updated_at in ascending order' do
        user1_order1.update!(state_updated_at: Time.now)
        result = client.execute(query, buyerId: user_id, sort: 'STATE_UPDATED_AT_ASC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_order2.id, user1_offer_order1.id, user1_order1.id])
      end

      it 'sorts by state_updated_at in descending order' do
        user1_order1.update!(state_updated_at: Time.now)
        result = client.execute(query, buyerId: user_id, sort: 'STATE_UPDATED_AT_DESC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_order1.id, user1_offer_order1.id, user1_order2.id])
      end

      it 'sorts by state_expires_at in ascending order' do
        user1_order1.update!(state_expires_at: 1.day.from_now)
        user1_order2.update!(state_expires_at: 2.days.from_now)
        result = client.execute(query, buyerId: user_id, sort: 'STATE_EXPIRES_AT_ASC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_order1.id, user1_offer_order1.id, user1_order2.id])
      end

      it 'sorts by state_expires_at in descending order' do
        user1_order1.update!(state_expires_at: 1.day.from_now)
        user1_order2.update!(state_expires_at: 2.days.from_now)
        result = client.execute(query, buyerId: user_id, sort: 'STATE_EXPIRES_AT_DESC')
        ids = ids_from_result_data(result)
        expect(ids).to eq([user1_order2.id, user1_offer_order1.id, user1_order1.id])
      end
    end

    context 'trusted user rules' do
      let(:jwt_user_id) { 'rando' }

      context 'trusted account accessing another account\'s order' do
        let(:jwt_roles) { 'trusted' }
        it 'allows access' do
          expect do
            client.execute(query, buyerId: 'someone-elses-userid')
          end.to_not raise_error
        end
      end

      context 'un-trusted account accessing another account\'s order' do
        let(:jwt_roles) { 'foobar' }
        it 'raises error' do
          expect do
            client.execute(query, buyerId: 'someone-elses-userid')
          end.to raise_error do |error|
            expect(error).to be_a(Graphlient::Errors::ServerError)
            expect(error.status_code).to eq 404
            expect(error.message).to eq 'the server responded with status 404'
            expect(error.response['errors'].first['extensions']['code']).to eq 'not_found'
            expect(error.response['errors'].first['extensions']['type']).to eq 'validation'
          end
        end
      end
    end

    describe 'total_count' do
      let(:query_with_total_count) do
        <<-GRAPHQL
          query($sellerId: String, $buyerId: String, $state: OrderStateEnum, $sort: OrderConnectionSortEnum) {
            orders(sellerId: $sellerId, buyerId: $buyerId, state: $state, sort: $sort, first: 2) {
              totalCount
              edges {
                node {
                  id
                }
              }
            }
          }
        GRAPHQL
      end
      before do
        Fabricate.times(10, :order, seller_type: 'partner', seller_id: seller_id)
      end
      it 'returns proper total count' do
        results = client.execute(query_with_total_count, sellerId: seller_id)
        expect(results.data.orders.total_count).to eq 12
        expect(results.data.orders.edges.count).to eq 2
      end
    end
  end
end
