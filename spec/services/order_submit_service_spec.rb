require 'rails_helper'
require 'support/gravity_helper'

describe OrderSubmitService, type: :services do
  include_context 'use stripe mock'

  let(:seller_id) { 'partner-1' }
  let(:credit_card_id) { 'cc-1' }
  let(:user_id) { 'dr-collector' }
  let(:order) do
    Fabricate(
      :order,
      seller_id: seller_id,
      credit_card_id: credit_card_id,
      fulfillment_type: Order::PICKUP
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
  let(:artwork_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }).to_return(status: 200, body: {}.to_json) }
  let(:edition_set_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-2/edition_set/es-1/inventory").with(body: { deduct: 2 }).to_return(status: 200, body: {}.to_json) }
  let(:artwork_inventory_undeduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { undeduct: 1 }).to_return(status: 200, body: {}.to_json) }
  let(:edition_set_inventory_undeduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-2/edition_set/es-1/inventory").with(body: { undeduct: 2 }).to_return(status: 200, body: {}.to_json) }
  let(:service) { OrderSubmitService.new(order, user_id) }
  describe '#process!' do
    context 'with a partner with a merchant account' do
      before do
        allow(GravityService).to receive(:get_merchant_account).with(seller_id).and_return(partner_merchant_accounts.first)
        allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
        allow(GravityService).to receive(:get_artwork).with(artwork1[:_id]).and_return(artwork1)
        allow(GravityService).to receive(:get_artwork).with(artwork2[:_id]).and_return(artwork2)
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all").and_return(gravity_v1_partner)
      end
      context 'with failed artwork inventory deduct' do
        let(:artwork_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }).to_return(status: 400, body: { message: 'could not deduct' }.to_json) }
        before do
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          artwork_inventory_undeduct_request
          edition_set_inventory_undeduct_request
        end
        it 'raises proper error response' do
          expect do
            service.process!
          end.to raise_error do |error|
            expect(error).to be_a(Errors::ProcessingError)
            expect(error.type).to eq :processing
            expect(error.code).to eq :insufficient_inventory
            expect(line_items.pluck(:id)).to include error.data[:line_item_id]
          end
        end
        it 'does not call to update edition set inventory' do
          expect do
            service.process!
          end.to raise_error(Errors::ProcessingError).and change(order.transactions, :count).by(0)
          expect(artwork_inventory_deduct_request).to have_been_requested
          expect(edition_set_inventory_deduct_request).to_not have_been_requested
          expect(artwork_inventory_undeduct_request).not_to have_been_requested
          expect(edition_set_inventory_undeduct_request).not_to have_been_requested
        end
      end
      context 'with failed edition_set inventory deduct' do
        let(:edition_set_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-2/edition_set/es-1/inventory").with(body: { deduct: 2 }).to_return(status: 400, body: { message: 'could not deduct edition' }.to_json) }
        before do
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          artwork_inventory_undeduct_request
          edition_set_inventory_undeduct_request
          expect do
            service.process!
          end.to raise_error(Errors::ProcessingError).and change(order.transactions, :count).by(0)
        end
        it 'deducts and then undeducts artwork inventory' do
          expect(artwork_inventory_deduct_request).to have_been_requested
          expect(edition_set_inventory_deduct_request).to have_been_requested
          expect(artwork_inventory_undeduct_request).to have_been_requested
          expect(edition_set_inventory_undeduct_request).not_to have_been_requested
        end
      end
      context 'with a successful transaction' do
        before(:each) do
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          service.process!
        end

        it 'calls gravity to update inventory' do
          expect(artwork_inventory_deduct_request).to have_been_requested
          expect(edition_set_inventory_deduct_request).to have_been_requested
        end
        it 'creates a record of the transaction' do
          expect(order.transactions.last.external_id).not_to be_nil
          expect(order.transactions.last.transaction_type).to eq Transaction::HOLD
          expect(order.transactions.last.status).to eq Transaction::SUCCESS
        end

        it 'updates the order expiration time' do
          expect(order.state_expires_at).to eq(order.state_updated_at + 2.days)
        end

        it 'updates the order state to SUBMITTED' do
          expect(order.state).to eq Order::SUBMITTED
          expect(order.state_updated_at).not_to be_nil
        end

        it 'updates external_charge_id with the id of the charge' do
          expect(order.external_charge_id).not_to be_nil
        end

        it 'queues a job for posting event' do
          expect(PostOrderNotificationJob).to have_been_enqueued
        end

        it 'does not queue a job for posting transaction event' do
          expect(PostTransactionNotificationJob).not_to have_been_enqueued
        end

        it 'queues a job for rejecting the order when it expires' do
          job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
          expect(job).to_not be_nil
          expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
          expect(job[:args][0]).to eq order.id
          expect(job[:args][1]).to eq Order::SUBMITTED
        end

        it 'sets commission_fee_cents' do
          expect(order.commission_fee_cents).to eq 14400_00
        end

        it 'sets transaction_fee_cents' do
          expect(order.transaction_fee_cents).to eq 522_30
        end
      end

      context 'with failed Stripe transaction' do
        before do
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          artwork_inventory_undeduct_request
          edition_set_inventory_undeduct_request
          StripeMock.prepare_card_error(:card_declined, :new_charge)
          allow(GravityService).to receive(:get_merchant_account).with(seller_id).and_return(partner_merchant_accounts.first)
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
          expect(PostOrderNotificationJob).not_to receive(:perform_later)
          expect(OrderFollowUpJob).not_to receive(:perform_later)
          expect { service.process! }.to raise_error do |error|
            expect(error).to be_a(Errors::ProcessingError)
            expect(error.code).to eq :charge_authorization_failed
            expect(error.data[:failure_code]).to eq 'card_declined'
          end
        end
        it 'deducts and then undeducts the inventory for both artwork and edition set' do
          expect(artwork_inventory_deduct_request).to have_been_requested
          expect(edition_set_inventory_deduct_request).to have_been_requested
          expect(artwork_inventory_undeduct_request).to have_been_requested
          expect(edition_set_inventory_undeduct_request).to have_been_requested
        end
        it 'records failed transaction' do
          expect(order.transactions.last.transaction_type).to eq Transaction::HOLD
          expect(order.transactions.last.status).to eq Transaction::FAILURE
          expect(order.transactions.last.failure_code).to eq 'card_declined'
        end
        it 'queues a job for posting transaction event' do
          expect(PostTransactionNotificationJob).to have_been_enqueued
        end
        it 'keeps order in pending' do
          expect(order.reload.state).to eq Order::PENDING
        end
        it 'does not update order external_charge_id' do
          expect(order.reload.external_charge_id).to be_nil
        end
      end

      describe 'Stripe call' do
        let(:seller_type) { 'gallery' }
        let(:order) do
          Fabricate(
            :order,
            seller_id: seller_id,
            seller_type: seller_type,
            credit_card_id: credit_card_id,
            fulfillment_type: Order::PICKUP,
            items_total_cents: 18000_00,
            tax_total_cents: 200_00,
            shipping_total_cents: 100_00
          )
        end
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
            capture: false
          ).and_return(uncaptured_charge)
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
          service.process!
        end
        context 'auction seller type' do
          let(:seller_type) { 'auction' }
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
                seller_type: 'auction',
                type: 'auction-bn'
              },
              destination: {
                account: 'ma-1',
                amount: 3369_00
              },
              capture: false
            ).and_return(uncaptured_charge)
            artwork_inventory_deduct_request
            edition_set_inventory_deduct_request
            service.process!
          end
        end
      end
    end
  end
end
