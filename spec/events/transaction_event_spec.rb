require 'rails_helper'

describe TransactionEvent, type: :events do
  let(:seller_id) { 'partner-1' }
  let(:user_id) { 'user-1' }
  let(:shipping_info) do
    {
      fulfillment_type: Order::SHIP,
      shipping_name: 'Fname Lname',
      shipping_address_line1: '123 Main St',
      shipping_address_line2: 'Apt 2',
      shipping_city: 'Chicago',
      shipping_country: 'USA',
      shipping_postal_code: '60618',
      shipping_region: 'IL'
    }
  end
  let(:order) do
    Fabricate(:order,
              buyer_id: user_id,
              buyer_type: Order::USER,
              buyer_phone_number: '00123459876',
              seller_id: seller_id,
              seller_type: 'gallery',
              currency_code: 'usd',
              shipping_total_cents: 50,
              tax_total_cents: 30,
              items_total_cents: 300,
              buyer_total_cents: 380,
              **shipping_info)
  end
  let(:transaction) { Fabricate(:transaction, order: order, failure_code: 'stolen_card', failure_message: 'who stole it?', status: Transaction::FAILURE) }
  let(:line_item1) { Fabricate(:line_item, list_price_cents: 200, order: order, commission_fee_cents: 40) }
  let(:line_item2) { Fabricate(:line_item, list_price_cents: 100, quantity: 2, order: order, commission_fee_cents: 20) }
  let!(:line_items) { [line_item1, line_item2] }
  let(:line_item_properties) do
    [
      {
        price_cents: 200,
        list_price_cents: 200,
        artwork_id: line_item1.artwork_id,
        edition_set_id: line_item1.edition_set_id,
        quantity: 1,
        commission_fee_cents: 40
      },
      {
        price_cents: 100,
        list_price_cents: 100,
        artwork_id: line_item2.artwork_id,
        edition_set_id: line_item2.edition_set_id,
        quantity: 2,
        commission_fee_cents: 20
      }
    ]
  end
  let(:event) { TransactionEvent.new(user: user_id, action: TransactionEvent::CREATED, model: transaction) }

  describe 'post' do
    it 'calls ArtsyEventService to post event' do
      expect(Artsy::EventService).to receive(:post_event).with(topic: 'commerce', event: instance_of(TransactionEvent))
      TransactionEvent.post(order, TransactionEvent::CREATED, user_id)
    end
  end

  describe '#subject' do
    it 'returns user id' do
      expect(event.subject[:id]).to eq user_id
    end
  end

  describe '#object' do
    it 'returns order id' do
      expect(event.object[:id]).to eq transaction.id.to_s
    end
  end

  describe '#properties' do
    it 'returns correct properties for a submitted order' do
      order.submit!
      expect(event.properties[:order][:id]).to eq order.id
      expect(event.properties[:order][:mode]).to eq Order::BUY
      expect(event.properties[:order][:code]).to eq order.code
      expect(event.properties[:order][:currency_code]).to eq 'USD'
      expect(event.properties[:order][:state]).to eq 'submitted'
      expect(event.properties[:order][:buyer_id]).to eq user_id
      expect(event.properties[:order][:buyer_type]).to eq Order::USER
      expect(event.properties[:order][:fulfillment_type]).to eq Order::SHIP
      expect(event.properties[:order][:seller_id]).to eq seller_id
      expect(event.properties[:order][:seller_type]).to eq 'gallery'
      expect(event.properties[:order][:items_total_cents]).to eq 300
      expect(event.properties[:order][:updated_at]).not_to be_nil
      expect(event.properties[:order][:created_at]).not_to be_nil
      expect(event.properties[:order][:line_items].count).to eq 2
      expect(event.properties[:order][:line_items]).to match_array(line_item_properties)
      expect(event.properties[:failure_code]).to eq 'stolen_card'
      expect(event.properties[:failure_message]).to eq 'who stole it?'
      expect(event.properties[:status]).to eq Transaction::FAILURE
    end
  end
end
