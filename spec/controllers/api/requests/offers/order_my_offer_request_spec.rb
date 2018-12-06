require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'order query' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:buyer_id) { jwt_user_id }
    let(:seller_user_id) { 'user2' }
    let!(:order) do
      Fabricate(
        :order,
        mode: Order::OFFER,
        seller_id: seller_id,
        seller_type: 'gallery',
        buyer_id: buyer_id,
        buyer_type: Order::USER,
        shipping_total_cents: 100_00,
        commission_fee_cents: 50_00,
        commission_rate: 0.10,
        seller_total_cents: 50_00,
        buyer_total_cents: 100_00,
        items_total_cents: 0,
        state: Order::SUBMITTED
      )
    end
    let(:buyer_offer1) { Fabricate(:offer, order: order, amount_cents: 200, from_id: buyer_id, from_type: Order::USER, creator_id: buyer_id, submitted_at: 2.days.ago, created_at: 2.days.ago) }
    let(:buyer_offer2) { Fabricate(:offer, order: order, amount_cents: 300, from_id: buyer_id, from_type: Order::USER, creator_id: buyer_id, created_at: 1.day.ago, shipping_total_cents: 100_00, tax_total_cents: 200_00) }
    let(:seller_offer) { Fabricate(:offer, order: order, amount_cents: 200, from_id: seller_id, from_type: 'gallery', creator_id: seller_user_id, submitted_at: Date.new(2018, 1, 2)) }
    let(:query) do
      <<-GRAPHQL
        query($id: ID) {
          order(id: $id) {
            id
            mode
            ... on OfferOrder {
              myLastOffer {
                id
                amountCents
                shippingTotalCents
                taxTotalCents
                from {
                  ... on User {
                    id
                  }
                }
              }
              offers{
                edges {
                  node {
                    id
                    fromParticipant
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    context 'user accessing their order' do
      context 'with no offers' do
        it 'returns empty myLastOffer' do
          result = client.execute(query, id: order.id)
          expect(result.data.order.my_last_offer).to be_nil
        end
      end
      context 'with offers' do
        before do
          buyer_offer1
          buyer_offer2
          seller_offer
          @result = client.execute(query, id: order.id)
        end
        it 'returns current pending offer for myLastOffer' do
          expect(@result.data.order.my_last_offer.id).to eq buyer_offer2.id
          expect(@result.data.order.my_last_offer.shipping_total_cents).to eq 100_00
          expect(@result.data.order.my_last_offer.tax_total_cents).to eq 200_00
        end
        it 'returns all submitted offers for order.offers' do
          expect(@result.data.order.offers.edges.count).to eq 2
          expect(@result.data.order.offers.edges.map(&:node).map(&:id)).to match_array [buyer_offer1.id, seller_offer.id]
          expect(@result.data.order.offers.edges.first.node.from_participant).to eq 'SELLER'
          expect(@result.data.order.offers.edges.last.node.from_participant).to eq 'BUYER'
        end
      end
    end

    context 'trusted app' do
      let(:jwt_user_id) { nil }
      let(:jwt_roles) { 'trusted' }
      before do
        buyer_offer1
        buyer_offer2
        seller_offer
      end
      context "trusted account accessing another account's order" do
        let(:buyer_id) { 'some-user' }
        it 'returns nil' do
          result = client.execute(query, id: order.id)
          expect(result.data.order.my_last_offer).to be_nil
        end
      end
    end

    context 'partner accessing order' do
      let(:buyer_id) { 'someone-else-id' }
      let(:seller_user_id) { jwt_user_id }
      before do
        buyer_offer1
        buyer_offer2
        seller_offer
      end
      it 'returns correct myLastOffer' do
        result = client.execute(query, id: order.id)
        expect(result.data.order.my_last_offer.id).to eq seller_offer.id
      end
    end
  end
end
