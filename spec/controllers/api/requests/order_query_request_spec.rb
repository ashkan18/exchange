require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'order query' do
    include_context 'GraphQL Client'
    let(:partner_id) { jwt_partner_ids.first }
    let(:second_partner_id) { 'partner-2' }
    let(:user_id) { jwt_user_id }
    let(:second_user) { 'user2' }
    let(:state) { Order::PENDING }
    let(:created_at) { 2.days.ago }
    let(:order_mode) { Order::BUY }
    let!(:user1_order1) do
      Fabricate(
        :order,
        seller_id: partner_id,
        seller_type: 'partner',
        buyer_id: user_id,
        buyer_type: 'user',
        created_at: created_at,
        updated_at: 1.day.ago,
        shipping_total_cents: 100_00,
        commission_fee_cents: 50_00,
        commission_rate: 0.10,
        seller_total_cents: 50_00,
        buyer_total_cents: 100_00,
        items_total_cents: 0,
        state: state,
        state_reason: state == Order::CANCELED ? 'seller_lapsed' : nil
      )
    end
    let!(:user2_order1) { Fabricate(:order, seller_id: second_partner_id, seller_type: 'partner', buyer_id: second_user, buyer_type: 'user') }

    let(:query) do
      <<-GRAPHQL
        query($id: ID, $offerFromId: String, $offerFromType: String) {
          order(id: $id) {
            id
            mode
            buyer {
              ... on User {
                id
              }
            }
            seller {
              ... on Partner {
                id
              }
            }
            state
            stateReason
            currencyCode
            itemsTotalCents
            shippingTotalCents
            sellerTotalCents
            buyerTotalCents
            createdAt
            displayCommissionRate
            lastOffer {
              id
              amountCents
              respondsTo {
                id
              }
              from {
                __typename
                ... on User {
                  id
                }
                ... on Partner {
                  id
                }
              }
            }
            lineItems {
              edges {
                node {
                  id
                  priceCents
                  artworkId
                  editionSetId
                }
              }
            }
            offers(fromId: $offerFromId, fromType: $offerFromType) {
              edges {
                node {
                  id
                  amountCents
                  from {
                    __typename
                    ... on User {
                      id
                    }
                    ... on Partner {
                      id
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    let(:query_by_code) do
      <<-GRAPHQL
        query($code: String) {
          order(code: $code) {
            id
            buyer {
              ... on User {
                id
              }
            }
            seller {
              ... on Partner {
                id
              }
            }
            state
            stateReason
            currencyCode
            itemsTotalCents
            shippingTotalCents
            sellerTotalCents
            buyerTotalCents
            createdAt
            lastOffer {
              id
              amountCents
              respondsTo {
                id
              }
              from {
                __typename
                ... on User {
                  id
                }
                ... on Partner {
                  id
                }
              }
            }
            lineItems {
              edges {
                node {
                  id
                  priceCents
                }
              }
            }
            offers {
              edges {
                node {
                  id
                  amountCents
                }
              }
            }
          }
        }
      GRAPHQL
    end

    context 'user accessing their order' do
      it 'returns not found error when query for orders by user not in jwt' do
        expect do
          client.execute(query, id: user2_order1.id)
        end.to raise_error do |error|
          expect(error).to be_a(Graphlient::Errors::ServerError)
          expect(error.message).to eq 'the server responded with status 404'
          expect(error.status_code).to eq 404
          expect(error.response['errors'].first['extensions']['code']).to eq 'not_found'
          expect(error.response['errors'].first['extensions']['type']).to eq 'validation'
        end
      end

      it 'returns order when accessing correct order' do
        result = client.execute(query, id: user1_order1.id)
        expect(result.data.order.mode).to eq 'BUY'
        expect(result.data.order.buyer.id).to eq user_id
        expect(result.data.order.seller.id).to eq partner_id
        expect(result.data.order.currency_code).to eq 'USD'
        expect(result.data.order.state).to eq 'PENDING'
        expect(result.data.order.items_total_cents).to eq 0
        expect(result.data.order.seller_total_cents).to eq 50_00
        expect(result.data.order.buyer_total_cents).to eq 100_00
        expect(result.data.order.created_at).to eq created_at.iso8601
      end

      it 'returns order when accessing correct order by code' do
        result = client.execute(query_by_code, code: user1_order1.code)
        expect(result.data.order.buyer.id).to eq user_id
        expect(result.data.order.seller.id).to eq partner_id
        expect(result.data.order.currency_code).to eq 'USD'
        expect(result.data.order.state).to eq 'PENDING'
        expect(result.data.order.items_total_cents).to eq 0
        expect(result.data.order.seller_total_cents).to eq 50_00
        expect(result.data.order.buyer_total_cents).to eq 100_00
        expect(result.data.order.created_at).to eq created_at.iso8601
      end

      it 'formats commission_rate into a display string' do
        result = client.execute(query, id: user1_order1.id)
        expect(result.data.order.display_commission_rate).to eq '10%'
      end

      context 'with line items' do
        let!(:order1_line_item1) { Fabricate(:line_item, order: user1_order1, artwork_id: 'artwork1', edition_set_id: 'edi-1') }
        let!(:order1_line_item2) { Fabricate(:line_item, order: user1_order1, artwork_id: 'artwork2', edition_set_id: 'edi-2') }
        it 'includes line items' do
          result = client.execute(query, id: user1_order1.id)
          expect(result.data.order.line_items.edges.count).to eq 2
          expect(result.data.order.line_items.edges.map(&:node).map(&:id)).to match_array [order1_line_item1.id, order1_line_item2.id]
          expect(result.data.order.line_items.edges.map(&:node).map(&:artwork_id)).to match_array %w[artwork1 artwork2]
          expect(result.data.order.line_items.edges.map(&:node).map(&:edition_set_id)).to match_array %w[edi-1 edi-2]
        end
      end

      context 'with offers' do
        let(:order_mode) { Order::OFFER }
        let!(:offer1) { Fabricate(:offer, order: user1_order1, amount_cents: 200, from_id: user_id, from_type: Order::USER) }
        let!(:offer2) { Fabricate(:offer, order: user1_order1, amount_cents: 300, from_id: partner_id, from_type: 'gallery', responds_to_id: offer1.id) }
        before do
          user1_order1.update! last_offer: offer2
        end
        it 'includes offers' do
          result = client.execute(query, id: user1_order1.id)
          expect(result.data.order.offers.edges.count).to eq 2
          expect(result.data.order.offers.edges.map(&:node).map(&:id)).to match_array [offer1.id, offer2.id]
          expect(result.data.order.offers.edges.map(&:node).map(&:amount_cents)).to match_array [200, 300]
          expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:id)).to match_array [user_id, partner_id]
          expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:__typename)).to match_array %w[User Partner]
        end
        it 'includes last_offer' do
          result = client.execute(query, id: user1_order1.id)
          expect(result.data.order.last_offer.id).to eq offer2.id
          expect(result.data.order.last_offer.from.id).to eq partner_id
          expect(result.data.order.last_offer.from.__typename).to eq 'Partner'
          expect(result.data.order.last_offer.responds_to.id).to eq offer1.id
        end
        describe 'offer filters' do
          it 'filters by from id' do
            result = client.execute(query, id: user1_order1.id, offerFromId: user_id)
            expect(result.data.order.offers.edges.count).to eq 1
            expect(result.data.order.offers.edges.map(&:node).map(&:id)).to eq [offer1.id]
            expect(result.data.order.offers.edges.map(&:node).map(&:amount_cents)).to eq [200]
            expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:id)).to eq [user_id]
            expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:__typename)).to eq %w[User]
          end
          it 'filters by from type' do
            result = client.execute(query, id: user1_order1.id, offerFromType: 'gallery')
            expect(result.data.order.offers.edges.count).to eq 1
            expect(result.data.order.offers.edges.map(&:node).map(&:id)).to eq [offer2.id]
            expect(result.data.order.offers.edges.map(&:node).map(&:amount_cents)).to eq [300]
            expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:id)).to eq [partner_id]
            expect(result.data.order.offers.edges.map(&:node).map(&:from).map(&:__typename)).to eq %w[Partner]
          end
        end
      end

      Order::STATES.each do |state|
        # https://github.com/artsy/exchange/issues/88
        context "order in #{state} state" do
          let(:state) { state }
          it 'returns proper state' do
            result = client.execute(query, id: user1_order1.id)
            expect(result.data.order.state).to eq state.upcase
          end
        end
      end

      context 'when state is CANCELED' do
        let(:state) { Order::CANCELED }
        it 'returns state_reason' do
          result = client.execute(query, id: user1_order1.id)
          expect(result.data.order.state_reason).to eq 'seller_lapsed'
        end
      end
    end

    context 'trusted user rules' do
      let(:jwt_user_id) { 'rando' }

      context "trusted account accessing another account's order" do
        let(:jwt_roles) { 'trusted' }

        it 'allows action' do
          expect do
            client.execute(query, id: user2_order1.id)
          end.to_not raise_error
        end

        it 'returns expected payload' do
          result = client.execute(query, id: user2_order1.id)
          expect(result.data.order.buyer.id).to eq user2_order1.buyer_id
          expect(result.data.order.seller.id).to eq user2_order1.seller_id
          expect(result.data.order.currency_code).to eq 'USD'
          expect(result.data.order.state).to eq 'PENDING'
          expect(result.data.order.items_total_cents).to eq 0
        end

        it 'cannot access seller_only fields' do
          # TODO: we may want to change this logic later but for now not allowing
          # those fields for trusted apps
          result = client.execute(query, id: user2_order1.id)
          expect(result.data.order.seller_total_cents).to be_nil
        end
      end

      context 'untrusted account accessing another account\'s order' do
        let(:jwt_roles) { 'foobar' }

        it 'raises error' do
          expect do
            client.execute(query, id: user2_order1.id)
          end.to raise_error do |error|
            expect(error).to be_a(Graphlient::Errors::ServerError)
            expect(error.message).to eq 'the server responded with status 404'
            expect(error.status_code).to eq 404
            expect(error.response['errors'].first['extensions']['code']).to eq 'not_found'
            expect(error.response['errors'].first['extensions']['type']).to eq 'validation'
          end
        end
      end

      context "sales admin accessing another account's order" do
        let(:jwt_roles) { 'sales_admin' }

        it 'allows action' do
          expect do
            client.execute(query, id: user2_order1.id)
          end.to_not raise_error
        end

        it 'returns expected payload' do
          result = client.execute(query, id: user2_order1.id)
          expect(result.data.order.buyer.id).to eq user2_order1.buyer_id
          expect(result.data.order.seller.id).to eq user2_order1.seller_id
          expect(result.data.order.currency_code).to eq 'USD'
          expect(result.data.order.state).to eq 'PENDING'
          expect(result.data.order.items_total_cents).to eq 0
        end
      end
    end

    context 'partner accessing order' do
      it 'returns order when accessing correct order' do
        another_user_order = Fabricate(:order, seller_id: partner_id, buyer_id: 'someone-else-id')
        result = client.execute(query, id: another_user_order.id)
        expect(result.data.order.buyer.id).to eq 'someone-else-id'
        expect(result.data.order.seller.id).to eq partner_id
        expect(result.data.order.currency_code).to eq 'USD'
        expect(result.data.order.state).to eq 'PENDING'
        expect(result.data.order.items_total_cents).to eq 0
      end
    end
  end
end
