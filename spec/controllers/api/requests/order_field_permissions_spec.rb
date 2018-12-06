require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'order query field permissions' do
    include_context 'GraphQL Client'
    let(:seller_id) { 'partner-1' }
    let(:user_id) { 'user-i' }
    let!(:order) do
      Fabricate(
        :order,
        seller_id: seller_id,
        buyer_id: user_id,
        updated_at: 1.day.ago,
        shipping_total_cents: 100_00,
        commission_fee_cents: 30_00,
        transaction_fee_cents: 20_00,
        items_total_cents: 1000_00,
        buyer_total_cents: 1100_00,
        seller_total_cents: 1050_00
      )
    end
    let!(:line_item) { Fabricate(:line_item, list_price_cents: 100_00, quantity: 2, commission_fee_cents: 40_00, order: order) }
    context 'as buyer' do
      let(:jwt_partner_ids) { [] }
      let(:jwt_user_id) { user_id }
      let(:order_query_with_seller_fields) do
        <<-GRAPHQL
          query($id: ID!) {
            order(id: $id) {
              id
              commissionFeeCents
              transactionFeeCents
              sellerTotalCents
              buyerTotalCents
              lineItems {
                edges {
                  node {
                    id
                    priceCents
                    listPriceCents
                    quantity
                    commissionFeeCents
                  }
                }
              }
            }
          }
        GRAPHQL
      end
      it 'returns nil for seller_only fields' do
        result = client.execute(order_query_with_seller_fields, id: order.id)
        expect(result.data.order.commission_fee_cents).to be_nil
        expect(result.data.order.transaction_fee_cents).to be_nil
        expect(result.data.order.seller_total_cents).to be_nil
        expect(result.data.order.buyer_total_cents).to eq 1100_00
        expect(result.data.order.line_items.edges.first.node.commission_fee_cents).to be_nil
        expect(result.data.order.line_items.edges.first.node.list_price_cents).to eq 100_00
      end
    end

    context 'as seller' do
      let(:jwt_user_id) { 'gallery-person-1' }
      let(:jwt_partner_ids) { [seller_id] }
      let(:order_query_with_buyer_fields) do
        <<-GRAPHQL
          query($id: ID!) {
            order(id: $id) {
              id
              buyerTotalCents
              commissionFeeCents
              sellerTotalCents
              lineItems {
                edges {
                  node {
                    id
                    priceCents
                    listPriceCents
                    quantity
                    commissionFeeCents
                  }
                }
              }
            }
          }
        GRAPHQL
      end
      it 'returns seller_only fields' do
        result = client.execute(order_query_with_buyer_fields, id: order.id)
        expect(result.data.order.buyer_total_cents).to eq 1100_00
        expect(result.data.order.seller_total_cents).to eq 1050_00
        expect(result.data.order.commission_fee_cents).to eq 30_00
        expect(result.data.order.line_items.edges.first.node.commission_fee_cents).to eq 40_00
        expect(result.data.order.line_items.edges.first.node.price_cents).to eq 100_00
        expect(result.data.order.line_items.edges.first.node.list_price_cents).to eq 100_00
      end
    end

    context 'as trusted app' do
      let(:jwt_user_id) { nil }
      let(:jwt_partner_ids) { nil }
      let(:jwt_roles) { 'artsy,trusted' }
      let(:order_query_with_buyer_fields) do
        <<-GRAPHQL
          query($id: ID!) {
            order(id: $id) {
              id
              buyerTotalCents
              commissionFeeCents
              sellerTotalCents
            }
          }
        GRAPHQL
      end
      it 'returns seller_only and buyer_only fields' do
        result = client.execute(order_query_with_buyer_fields, id: order.id)
        expect(result.data.order.buyer_total_cents).to eq 1100_00
        expect(result.data.order.seller_total_cents).to eq 1050_00
        expect(result.data.order.commission_fee_cents).to eq 30_00
      end
    end
  end
end
