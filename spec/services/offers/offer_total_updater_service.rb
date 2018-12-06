require 'rails_helper'

describe Offers::OfferTotalUpdaterService, type: :services do
  describe '#process!' do
    let!(:partner_id)  { 'partner-1' }
    let(:artwork_location) { { country: 'US' } }
    let(:artwork) { { _id: 'a-1', current_version_id: '1', location: artwork_location, domestic_shipping_fee_cents: 1000 } }
    let!(:order) { Fabricate(:order, state: Order::SUBMITTED, seller_id: partner_id, **shipping_info) }
    let!(:offer) { Fabricate(:offer, order: order, amount_cents: 10000) }
    let(:line_item_artwork_version) { artwork[:current_version_id] }
    let!(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: artwork[:_id], artwork_version_id: line_item_artwork_version, quantity: 2) }
    let(:partner_address) do
      Address.new(
        street_line1: '401 Broadway',
        country: 'US',
        city: 'New York',
        region: 'NY',
        postal_code: '10013'
      )
    end
    let(:shipping_info) do
      {
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'New York',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_region: 'NY',
        shipping_country: 'US',
        fulfillment_type: Order::SHIP
      }
    end
    let(:offer_tax) { 100 }
    let(:remit_tax) { false }
    let(:tax_calculator_service) { double }
    let(:service) { Offers::OfferTotalUpdaterService.new(offer: offer) }

    before do
      allow(Tax::CalculatorService).to receive(:new).with(
        offer.amount_cents,
        offer.amount_cents / order.line_items.first.quantity,
        order.line_items.first.quantity,
        order.fulfillment_type,
        instance_of(Address),
        1000,
        instance_of(Address),
        [partner_address]
      ).and_return(tax_calculator_service)
      allow(tax_calculator_service).to receive(:sales_tax).and_return(offer_tax)
      allow(tax_calculator_service).to receive(:artsy_should_remit_taxes?).and_return(remit_tax)
      allow(GravityService).to receive(:fetch_partner_locations).with(partner_id).and_return([partner_address])
      allow(GravityService).to receive(:get_artwork).and_return(artwork)
    end

    context 'with an offer' do
      it 'calculates tax and shipping for the offer' do
        service.process!
        expect(offer.shipping_total_cents).to eq(1000)
        expect(offer.tax_total_cents).to eq(offer_tax)
        expect(offer.should_remit_sales_tax).to eq(false)
      end
    end
  end
end
