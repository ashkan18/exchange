require 'rails_helper'

describe Offers::AcceptOfferService, type: :services do
  include_context 'use stripe mock'
  describe '#process!' do
    subject(:call_service) do
      described_class.new(
        offer: offer,
        order: order,
        user_id: current_user_id
      ).process!
    end
    let(:seller_id) { 'partner-1' }
    let(:credit_card_id) { 'cc-1' }
    let(:user_id) { 'dr-collector' }
    let(:order) do
      Fabricate(
        :order,
        state: Order::SUBMITTED,
        seller_id: seller_id,
        credit_card_id: credit_card_id,
        fulfillment_type: Order::PICKUP,
        items_total_cents: 18000_00,
        tax_total_cents: 200_00,
        shipping_total_cents: 100_00
      )
    end
    let(:artwork1) { { _id: 'a-1', current_version_id: '1' } }
    let(:artwork2) { { _id: 'a-2', current_version_id: '1' } }
    let!(:line_items) do
      [
        Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: artwork1[:_id], artwork_version_id: artwork1[:current_version_id], quantity: 1),
        Fabricate(:line_item, order: order, list_price_cents: 8000_00, artwork_id: artwork2[:_id], artwork_version_id: artwork2[:current_version_id], edition_set_id: 'es-1', quantity: 2)
      ]
    end
    let(:credit_card) { { external_id: stripe_customer.default_source, customer_account: { external_id: stripe_customer.id }, deactivated_at: nil } }
    let(:merchant_account_id) { 'ma-1' }
    let(:partner_merchant_accounts) { [{ external_id: 'ma-1' }, { external_id: 'some_account' }] }
    let(:create_charge_params) do
      {
        source_id: credit_card[:external_id],
        destination_id: merchant_account_id,
        customer_id: credit_card[:customer_account][:external_id],
        amount: order.buyer_total_cents,
        currency_code: order.currency_code
      }
    end
    let!(:offer) { Fabricate(:offer, order: order) }
    let(:current_user_id) { 'user-id-123' }
    let(:artwork_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }).to_return(status: 200, body: {}.to_json) }
    let(:edition_set_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-2/edition_set/es-1/inventory").with(body: { deduct: 2 }).to_return(status: 200, body: {}.to_json) }

    before do
      # last_offer is set in Orders::InitialOffer. "Stubbing" out the
      # dependent behavior of this class to by setting last_offer directly
      order.update!(last_offer: offer)
      allow(GravityService).to receive(:get_merchant_account).with(seller_id).and_return(partner_merchant_accounts.first)
      allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
      allow(GravityService).to receive(:get_artwork).with(artwork1[:_id]).and_return(artwork1)
      allow(GravityService).to receive(:get_artwork).with(artwork2[:_id]).and_return(artwork2)
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
      line_items.each do |li|
        allow(GravityService).to receive(:deduct_inventory).with(li)
      end
    end

    context 'with a approve-able order' do
      it 'updates the state of the order' do
        expect do
          call_service
        end.to change { order.state }.from(Order::SUBMITTED).to(Order::APPROVED)
      end

      it 'instruments an approved order' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.approve')

        call_service

        expect(dd_statsd).to have_received(:increment).with('order.approve')
      end

      it 'queues a PostOrderNotificationJob with the current user id with the approved action' do
        allow(PostOrderNotificationJob).to receive(:perform_later)

        call_service

        expect(PostOrderNotificationJob).to have_received(:perform_later)
          .with(order.id, Order::APPROVED, current_user_id)
      end

      describe 'Stripe call' do
        it 'calls stripe with expected params' do
          expect(Stripe::Charge).to receive(:create).with(
            amount: 18300_00,
            currency: 'USD',
            description: 'INVOICING-DE via Artsy',
            source: stripe_customer.default_source,
            customer: stripe_customer.id,
            metadata: {
              exchange_order_id: order.id,
              buyer_id: order.buyer_id,
              buyer_type: 'user',
              seller_id: 'partner-1',
              seller_type: 'gallery',
              type: 'bn-mo'
            },
            destination: {
              account: 'ma-1',
              amount: 3369_00
            },
            capture: true
          ).and_return(captured_charge)
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          call_service
        end
      end
    end

    context "when we can't approve the order" do
      before do
        order.update!(state: Order::PENDING)
      end

      it "doesn't instrument" do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.approve')

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end

      it 'does not queue a PostOrderNotificationJob' do
        allow(PostOrderNotificationJob).to receive(:perform_later)

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(PostOrderNotificationJob).to_not have_received(:perform_later)
          .with(order.id, Order::APPROVED, current_user_id)
      end
    end

    context 'attempting to accept not the last offer' do
      let!(:another_offer) { Fabricate(:offer, order: order) }

      before do
        # last_offer is set in Orders::InitialOffer. "Stubbing" out the
        # dependent behavior of this class to by setting last_offer directly
        order.update!(last_offer: another_offer)
      end

      it 'raises a validation error' do
        expect { call_service }
          .to raise_error(Errors::ValidationError)
      end

      it 'does not approve the order' do
        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(order.reload.state).to eq(Order::SUBMITTED)
      end

      it 'does not instrument' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.approve')

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end

      it 'does not queue a PostOrderNotificationJob' do
        allow(PostOrderNotificationJob).to receive(:perform_later)

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(PostOrderNotificationJob).to_not have_received(:perform_later)
          .with(order.id, Order::APPROVED, current_user_id)
      end
    end
  end

  def stub_ddstatsd_instance
    dd_statsd = double(Datadog::Statsd)
    allow(Exchange).to receive(:dogstatsd).and_return(dd_statsd)

    dd_statsd
  end
end
