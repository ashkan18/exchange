require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe Api::GraphqlController, type: :request do
  describe 'set_shipping mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:order) { Fabricate(:order, seller_id: seller_id, buyer_id: user_id) }
    let!(:line_items) { [Fabricate(:line_item, order: order, artwork_id: 'a-1'), Fabricate(:line_item, order: order, artwork_id: 'a-2')] }
    let(:artwork1) { gravity_v1_artwork(_id: 'a-1', domestic_shipping_fee_cents: 200_00, international_shipping_fee_cents: 300_00) }
    let(:artwork2) { gravity_v1_artwork(_id: 'a-2', domestic_shipping_fee_cents: 400_00, international_shipping_fee_cents: 500_00) }
    let(:shipping_country) { 'US' }
    let(:shipping_region) { 'NY' }
    let(:shipping_postal_code) { '10012' }
    let(:fulfillment_type) { 'SHIP' }
    let(:total_sales_tax) { 2222 }
    let(:phone_number) { '00123456789' }
    let(:partner) { { id: seller_id, artsy_collects_sales_tax: true, billing_location_id: '123abc' } }
    let(:seller_addresses) { [Address.new(state: 'NY', country: 'US', postal_code: '10001'), Address.new(state: 'MA', country: 'US', postal_code: '02139')] }
    let(:untaxable_seller_address) { [Address.new(country: 'FR')] }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SetShippingInput!) {
          setShipping(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  shippingTotalCents
                  requestedFulfillment {
                    __typename
                    ... on Ship {
                      addressLine1
                    }
                    ... on Pickup {
                      fulfillmentType
                    }
                  }
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
    let(:shipping_address) do
      {
        name: 'Fname Lname',
        country: shipping_country,
        city: 'New York',
        region: shipping_region,
        postalCode: shipping_postal_code,
        phoneNumber: phone_number,
        addressLine1: '401 Broadway',
        addressLine2: 'Suite 80'
      }
    end
    let(:set_shipping_input) do
      {
        input: {
          id: order.id.to_s,
          fulfillmentType: fulfillment_type,
          shipping: shipping_address
        }.compact
      }
    end

    before do
      stub_tax_for_order
    end

    context 'with user without permission to this order' do
      let(:user_id) { 'random-user-id-on-another-order' }
      it 'returns permission error' do
        response = client.execute(mutation, set_shipping_input)
        expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
        expect(response.data.set_shipping.order_or_error.error.code).to eq 'not_found'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with proper permission' do
      context 'with order in non-pending state' do
        before do
          order.update! state: Order::APPROVED
        end
        it 'returns error' do
          response = client.execute(mutation, set_shipping_input)
          expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
          expect(response.data.set_shipping.order_or_error.error.code).to eq 'invalid_state'
          expect(order.reload.state).to eq Order::APPROVED
        end
      end

      context 'Pickup Order' do
        let(:shipping_address) { nil }
        let(:fulfillment_type) { 'PICKUP' }
        before do
          allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
          allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
          allow(Gravity).to receive_messages(
            fetch_partner_locations: seller_addresses,
            fetch_partner: partner
          )
          @response = client.execute(mutation, set_shipping_input)
        end
        it 'sets fulfillment_type on the order' do
          expect(@response.data.set_shipping.order_or_error.order.requested_fulfillment.__typename).to eq 'Pickup'
          expect(@response.data.set_shipping.order_or_error.order.requested_fulfillment.fulfillment_type).to eq Order::PICKUP
          expect(order.reload.fulfillment_type).to eq Order::PICKUP
        end
        it 'calculates tax' do
          expect(line_items[0].reload.sales_tax_cents).to eq 116
          expect(line_items[1].reload.sales_tax_cents).to eq 116
          expect(line_items[0].reload.should_remit_sales_tax?).to eq false
          expect(line_items[1].reload.should_remit_sales_tax?).to eq false
          expect(order.reload.tax_total_cents).to eq 232
        end
        it 'sets shipping to 0' do
          expect(@response.data.set_shipping.order_or_error.order.shipping_total_cents).to eq 0
          expect(order.reload.shipping_total_cents).to eq 0
        end
      end
      context 'Ship Order' do
        before do
          allow(Gravity).to receive(:fetch_partner).and_return(partner)
        end
        context 'without passing phone number' do
          let(:phone_number) { nil }
          it 'fails' do
            expect do
              client.execute(mutation, set_shipping_input)
            end.to raise_error(/phoneNumber: Expected value to not be null/)
          end
        end

        context 'with no partner locations' do
          before do
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([])
          end
          it 'raises an error' do
            response = client.execute(mutation, set_shipping_input)
            expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
            expect(response.data.set_shipping.order_or_error.error.code).to eq 'missing_partner_location'
          end
        end

        context 'with untaxable partner locations' do
          before do
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([{ country: 'FR' }])
          end
          it 'sets sales tax to 0 and should_remit_sales_tax to false on each line item' do
            client.execute(mutation, set_shipping_input)
            expect(order.reload.tax_total_cents).to eq 0
            order.reload.line_items.each do |li|
              expect(li.sales_tax_cents).to eq 0
              expect(li.should_remit_sales_tax).to eq false
            end
          end
        end

        context 'with a shipping address with an unrecognized country' do
          let(:shipping_country) { 'ASDF' }
          before do
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([{ country: 'FR' }])
          end
          it 'returns proper error' do
            response = client.execute(mutation, set_shipping_input)
            expect(response.data.set_shipping.order_or_error).to respond_to(:error)
            expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
            expect(response.data.set_shipping.order_or_error.error.code).to eq 'missing_country'
          end
        end

        context 'with a US-based shipping address' do
          before do
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([{ country: 'US', state: 'NY' }])
          end
          let(:shipping_country) { 'US' }
          context 'without a state' do
            let(:shipping_region) { nil }
            it 'returns proper error' do
              response = client.execute(mutation, set_shipping_input)
              expect(response.data.set_shipping.order_or_error).to respond_to(:error)
              expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
              expect(response.data.set_shipping.order_or_error.error.code).to eq 'missing_region'
            end
          end
          context 'without a postal code' do
            let(:shipping_region) { 'FL' }
            let(:shipping_postal_code) { nil }
            it 'returns proper error' do
              response = client.execute(mutation, set_shipping_input)
              expect(response.data.set_shipping.order_or_error).to respond_to(:error)
              expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
              expect(response.data.set_shipping.order_or_error.error.code).to eq 'missing_postal_code'
            end
          end
        end

        context 'with artwork with missing location' do
          it 'returns an error' do
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([{ country: 'US', state: 'NY' }])
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(id: 'missing-location')
            response = client.execute(mutation, set_shipping_input)
            expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
            expect(response.data.set_shipping.order_or_error.error.code).to eq 'missing_artwork_location'
          end
        end

        context 'with failed artwork fetch call' do
          it 'returns an error' do
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([{ country: 'US', state: 'NY' }])
            allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_raise(Adapters::GravityError.new('unknown artwork'))
            response = client.execute(mutation, set_shipping_input)
            expect(response.data.set_shipping.order_or_error.error.type).to eq 'validation'
            expect(response.data.set_shipping.order_or_error.error.code).to eq 'unknown_artwork'
          end
        end

        it 'sets shipping info and sales tax on the order' do
          allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
          allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
          allow(Gravity).to receive(:fetch_partner_locations).and_return(seller_addresses)
          response = client.execute(mutation, set_shipping_input)
          expect(response.data.set_shipping.order_or_error.order.id).to eq order.id.to_s
          expect(response.data.set_shipping.order_or_error.order.state).to eq 'PENDING'
          expect(response.data.set_shipping.order_or_error).not_to respond_to(:error)
          expect(response.data.set_shipping.order_or_error.order.requested_fulfillment.address_line1).to eq '401 Broadway'
          expect(order.reload.fulfillment_type).to eq Order::SHIP
          expect(order.state).to eq Order::PENDING
          expect(order.shipping_country).to eq 'US'
          expect(order.shipping_city).to eq 'New York'
          expect(order.shipping_region).to eq 'NY'
          expect(order.shipping_postal_code).to eq '10012'
          expect(order.buyer_phone_number).to eq '00123456789'
          expect(order.shipping_name).to eq 'Fname Lname'
          expect(order.shipping_address_line1).to eq '401 Broadway'
          expect(order.shipping_address_line2).to eq 'Suite 80'
          expect(order.state_expires_at).to eq(order.state_updated_at + 2.days)
          expect(line_items[0].reload.sales_tax_cents).to eq 116
          expect(line_items[1].reload.sales_tax_cents).to eq 116
          expect(line_items[0].reload.should_remit_sales_tax?).to eq false
          expect(line_items[1].reload.should_remit_sales_tax?).to eq false
          expect(order.tax_total_cents).to eq 232
        end

        describe '#shipping_total_cents' do
          before do
            allow(Gravity).to receive(:fetch_partner_locations).and_return(seller_addresses)
          end
          context 'with PICKUP as fulfillment type' do
            before do
              expect(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
              expect(Adapters::GravityV1).to receive(:get).with('/artwork/a-2').and_return(artwork2)
            end
            let(:fulfillment_type) { 'PICKUP' }
            it 'sets total shipping cents to 0' do
              response = client.execute(mutation, set_shipping_input)
              expect(response.data.set_shipping.order_or_error.order.shipping_total_cents).to eq 0
              expect(order.reload.shipping_total_cents).to eq 0
            end
          end
          context 'with SHIP as fulfillment type' do
            before do
              expect(Adapters::GravityV1).to receive(:get).once.with('/artwork/a-1').and_return(artwork1)
              expect(Adapters::GravityV1).to receive(:get).once.with('/artwork/a-2').and_return(artwork2)
            end
            context 'with international shipping' do
              let(:shipping_country) { 'IR' }
              it 'sets total shipping cents properly' do
                response = client.execute(mutation, set_shipping_input)
                expect(response.data.set_shipping.order_or_error.order.shipping_total_cents).to eq 800_00
                expect(order.reload.shipping_total_cents).to eq 800_00
              end
            end

            context 'with domestic shipping' do
              it 'sets total shipping cents properly' do
                response = client.execute(mutation, set_shipping_input)
                expect(response.data.set_shipping.order_or_error.order.shipping_total_cents).to eq 600_00
                expect(order.reload.shipping_total_cents).to eq 600_00
              end
            end

            context 'with one free shipping artwork' do
              let(:artwork1) { gravity_v1_artwork(_id: 'a-1', domestic_shipping_fee_cents: 0, international_shipping_fee_cents: 0) }
              it 'sets total shipping cents only based on non-free shipping artwork' do
                response = client.execute(mutation, set_shipping_input)
                expect(response.data.set_shipping.order_or_error.order.shipping_total_cents).to eq 400_00
                expect(order.reload.shipping_total_cents).to eq 400_00
              end
            end
          end
        end
      end
    end
  end
end
