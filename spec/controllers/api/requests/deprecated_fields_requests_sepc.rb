require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'order deprecated fields' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:buyer_id) { jwt_user_id }
    let(:seller_id) { 'user2' }
    let!(:order) do
      Fabricate(
        :order,
        mode: Order::OFFER,
        seller_id: seller_id,
        seller_type: 'partner',
        buyer_id: buyer_id,
        buyer_type: 'user',
        shipping_total_cents: 100_00,
        commission_fee_cents: 50_00,
        commission_rate: 0.10,
        seller_total_cents: 50_00,
        buyer_total_cents: 100_00,
        items_total_cents: 420,
        state: Order::SUBMITTED
      )
    end
    let!(:order1_line_item1) { Fabricate(:line_item, order: order, artwork_id: 'artwork1', edition_set_id: 'edi-1', list_price_cents: 200_00) }
    let!(:buyer_offer1) { Fabricate(:offer, order: order, amount_cents: 200, from_id: buyer_id, from_type: Order::USER, creator_id: buyer_id, submitted_at: 2.days.ago, created_at: 2.days.ago) }
    let!(:buyer_offer2) { Fabricate(:offer, order: order, amount_cents: 300, from_id: buyer_id, from_type: Order::USER, creator_id: buyer_id, created_at: 1.day.ago) }
    let(:query) do
      <<-GRAPHQL
        query($id: ID) {
          order(id: $id) {
            id
            mode
            lastOffer {
              id
            }
            offers {
              edges {
                node {
                  id
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'includes lastOffer' do
      order.update!(last_offer: buyer_offer2)
      result = client.execute(query, id: order.id)
      expect(result.data.order.last_offer.id).to eq buyer_offer2.id
    end
    it 'includes offers' do
      result = client.execute(query, id: order.id)
      expect(result.data.order.offers.edges.map(&:node).map(&:id)).to match_array [buyer_offer1.id]
    end
  end
end
