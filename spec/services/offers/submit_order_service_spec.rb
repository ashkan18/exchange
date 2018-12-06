require 'rails_helper'
require 'support/gravity_helper'

describe Offers::SubmitOrderService, type: :services do
  let(:user_id) { 'user-id' }
  let(:seller_id) { 'partner-1' }
  let(:order_mode) { Order::OFFER }
  let(:order_state) { Order::PENDING }
  let(:offer_submitted_at) { nil }
  let(:shipping_info) do
    {
      shipping_name: 'Fname Lname',
      shipping_address_line1: '12 Vanak St',
      shipping_address_line2: 'P 80',
      shipping_city: 'Tehran',
      shipping_postal_code: '02198',
      buyer_phone_number: '00123456',
      shipping_country: 'IR',
      fulfillment_type: Order::SHIP
    }
  end
  let(:artwork) { { _id: 'a-1', current_version_id: '1' } }
  let(:line_item_artwork_version) { artwork[:current_version_id] }
  let(:credit_card_id) { 'grav_c_id1' }
  let(:credit_card) { { external_id: 'cc-1', customer_account: { external_id: 'cus-1' }, deactivated_at: nil } }
  let(:order) { Fabricate(:order, seller_id: seller_id, mode: order_mode, state: order_state, credit_card_id: credit_card_id, **shipping_info) }
  let!(:offer) { Fabricate(:offer, order: order, submitted_at: offer_submitted_at, amount_cents: 1000_00, tax_total_cents: 20_00, shipping_total_cents: 30_00) }
  let!(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: artwork[:_id], artwork_version_id: line_item_artwork_version, quantity: 2) }
  let(:service) { described_class.new(offer, user_id: user_id) }
  describe '#process!' do
    describe 'failed process' do
      before do
        order.update!(last_offer: offer)
        expect(PostOrderNotificationJob).not_to receive(:perform_later)
        expect(OrderFollowUpJob).not_to receive(:perform_later)
        expect(ReminderFollowUpJob).not_to receive(:perform_later)
      end

      context 'without shipping info' do
        let(:shipping_info) { {} }
        it 'raises missing_required_info error' do
          expect { service.process! }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :missing_required_info
          end
        end
      end

      context 'without payment info' do
        let(:credit_card_id) { nil }
        it 'raises missing_required_info error' do
          expect { service.process! }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :missing_required_info
          end
        end
      end

      context 'artwork version mismatch' do
        let(:line_item_artwork_version) { 'some-other-version' }
        it 'raises artwork_version_mismatch error' do
          expect(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
          expect(Exchange).to receive_message_chain(:dogstatsd, :increment).with('submit.artwork_version_mismatch')
          expect { service.process! }.to raise_error do |e|
            expect(e.type).to eq :processing
            expect(e.code).to eq :artwork_version_mismatch
          end
        end
      end

      context 'Buy order' do
        let(:order_mode) { Order::BUY }
        it 'raises cant_submit error' do
          expect { service.process! }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :cant_submit
          end
        end
      end

      Order::STATES.reject { |s| [Order::CANCELED, Order::PENDING].include? s }.each do |state|
        context "#{state} order" do
          let(:order_state) { state }
          before do
            allow(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
            allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
            allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
          end
          it 'raises cant_submit error' do
            expect { service.process! }.to raise_error do |e|
              expect(e.type).to eq :validation
              expect(e.code).to eq :invalid_state
            end
          end
        end
      end

      describe '#assert_credit_card!' do
        before do
          allow(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
        end
        it 'raises an error if the credit card does not have an external id' do
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: nil)
          expect { service.process! }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_external_id
            expect(error.data).to match(credit_card_id: 'cc-1')
          end
        end

        it 'raises an error if the credit card does not have a customer account' do
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1')
          expect { service.process! }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_customer
            expect(error.data).to match(credit_card_id: 'cc-1')
          end
        end

        it 'raises an error if the credit card does not have a customer account external id' do
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { some_prop: 'some_val' }, deactivated_at: nil)
          expect { service.process! }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_customer
            expect(error.data).to match(credit_card_id: 'cc-1')
          end
        end

        it 'raises an error if the card is deactivated' do
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: 2.days.ago)
          expect { service.process! }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_deactivated
            expect(error.data).to match(credit_card_id: 'cc-1')
          end
        end
      end
    end

    describe 'successful process' do
      before do
        order.update!(last_offer: offer)
        allow(GravityService).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
        allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
        expect(Exchange).to receive_message_chain(:dogstatsd, :increment).with('order.submit')
        expect(PostOrderNotificationJob).to receive(:perform_later).once.with(order.id, Order::SUBMITTED, user_id)
      end
      it 'submits the offer' do
        expect do
          service.process!
          expect(order.reload.state).to eq(Order::SUBMITTED)
          expect(offer.reload.submitted_at).not_to be_nil
        end.to change(order.state_histories, :count).by(1)
      end

      it 'queues related jobs' do
        service.process!
        expect(OrderFollowUpJob).to have_been_enqueued
        expect(ReminderFollowUpJob).to have_been_enqueued
      end

      it 'updates orders last_offer' do
        service.process!
        expect(order.reload.last_offer).to eq offer
      end

      it 'updates order totals' do
        service.process!
        expect(order.commission_fee_cents).to eq offer.amount_cents * 0.8 # comes from gravity_v1_partner
        expect(order.shipping_total_cents).to eq 30_00
        expect(order.tax_total_cents).to eq 20_00
        expect(order.buyer_total_cents).to eq 1000_00 + 30_00 + 20_00
        expect(order.transaction_fee_cents).to eq(order.buyer_total_cents * 2.9 / 100 + 30)
      end
    end
  end
end
