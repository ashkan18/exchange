require 'rails_helper'
require 'support/gravity_helper'

describe Api::GraphqlController, type: :request do
  describe 'submit order with offer' do
    include_context 'GraphQL Client'

    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:artwork) { { _id: 'a-1', current_version_id: '1' } }
    let(:line_item_artwork_version) { artwork[:current_version_id] }
    let(:credit_card_id) { 'grav_c_id1' }
    let(:credit_card) { { external_id: 'cc-1', customer_account: { external_id: 'cus-1' }, deactivated_at: nil } }
    let(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: artwork[:_id], artwork_version_id: line_item_artwork_version, quantity: 2) }
    let(:order) do
      Fabricate(
        :order,
        mode: Order::OFFER,
        seller_id: seller_id,
        buyer_id: user_id,
        credit_card_id: credit_card_id,
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'Tehran',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_country: 'IR',
        fulfillment_type: Order::SHIP,
        items_total_cents: 1000_00,
        buyer_total_cents: 1000_00
      )
    end
    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SubmitOrderWithOfferInput!) {
          submitOrderWithOffer(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  ... on OfferOrder {
                    lastOffer {
                      id
                      submittedAt
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

    before do
      order.line_items << line_item
      Offers::InitialOfferService.new(order, 800_00, user_id).process!
      @offer = order.reload.offers.last
    end

    describe 'mutation is rejected' do
      let(:submit_order_input) do
        {
          input: {
            offerId: @offer.id.to_s
          }
        }
      end

      it 'if the offer from_id does not match the current user id' do
        user_id = 'random-user-id-on-another-order'
        @offer.update!(from_id: user_id)

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'not_found'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
      end

      it 'if the order is not in a pending state' do
        allow(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
        allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
        order.update!(state: 'abandoned')

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'invalid_state'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::ABANDONED
      end

      it 'if the offer has already been submitted' do
        @offer.update!(submitted_at: Time.now.utc)

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'invalid_offer'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
      end

      it 'if the order is missing payment info' do
        order.update!(credit_card_id: nil)

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'missing_required_info'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
      end

      it 'if the order is missing shipping info' do
        order.update!(shipping_name: nil)

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'missing_required_info'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
      end

      it 'if the order is not an offer order' do
        order.update!(mode: Order::BUY)

        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:order)
        expect(response.data.submit_order_with_offer.order_or_error.error.code).to eq 'cant_submit'
        expect(response.data.submit_order_with_offer.order_or_error.error.type).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    describe 'successful mutations' do
      let(:submit_order_input) do
        {
          input: {
            offerId: @offer.id.to_s
          }
        }
      end
      before do
        allow(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
        allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
      end

      it 'submits the order and updates submitted_at on the offer' do
        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order_with_offer.order_or_error).not_to respond_to(:error)
        expect(response.data.submit_order_with_offer.order_or_error.order.state).to eq 'SUBMITTED'
        expect(response.data.submit_order_with_offer.order_or_error.order.last_offer.id).to eq @offer.id
        expect(response.data.submit_order_with_offer.order_or_error.order.last_offer.submitted_at).to_not be_nil
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end
  end
end
