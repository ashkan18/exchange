require 'rails_helper'
require 'support/gravity_helper'

describe CommitOrderService, type: :services do
  include_context 'use stripe mock'

  let(:seller_id) { 'partner-1' }
  let(:partner) { { id: seller_id, effective_commission_rate: 0.01 } }
  let(:partner_missing_commission_rate) { { id: seller_id, effective_commission_rate: nil } }
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
  let(:service) { CommitOrderService.new(order, :submit, user_id) }
  let(:transaction) { Fabricate(:transaction, status: Transaction::SUCCESS) }
  let(:failed_transaction) { Fabricate(:transaction, status: Transaction::FAILURE) }

  describe '#pre_process!' do
    context 'with an uncommittable action' do
      it 'raises an error' do
        error_service = CommitOrderService.new(order, :reject, user_id)
        expect { error_service.send(:pre_process!) }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :uncommittable_action
        end
      end
    end
    context 'with correctly validated data' do
      it 'updates order totals with the partner commission rate' do
        allow(GravityService).to receive(:get_credit_card).and_return(credit_card)
        allow(GravityService).to receive(:get_artwork).and_return(artwork1)
        allow(GravityService).to receive(:get_artwork).and_return(artwork2)
        expect(GravityService).to receive(:fetch_partner).with(seller_id).and_return(partner)
        service.send(:pre_process!)
        expect(order.reload.commission_rate).to eq partner[:effective_commission_rate]
      end
    end
  end

  describe '#validate_commission_rate!' do
    context 'with a partner with missing commission rate' do
      it 'raises an error' do
        allow(GravityService).to receive(:fetch_partner).and_return(partner_missing_commission_rate)
        expect { service.send(:validate_commission_rate!) }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :missing_commission_rate
          expect(error.data).to match(partner_id: seller_id)
        end
      end
    end
  end

  describe '#validate_artwork_versions!' do
    context 'with mismatched artwork versions' do
      it 'raises an error and records the artwork mismatch in DataDog' do
        expect(GravityService).to receive(:get_artwork).with(artwork1[:_id]).and_return(artwork1.merge(current_version_id: 2))
        expect(Exchange).to receive_message_chain(:dogstatsd, :increment).with('submit.artwork_version_mismatch')
        expect { service.send(:validate_artwork_versions!) }.to raise_error do |error|
          expect(error).to be_a(Errors::ProcessingError)
          expect(error.code).to eq :artwork_version_mismatch
        end
      end
    end
  end

  describe '#deduct_inventory' do
    it 'deducts inventory for each line item' do
      order.line_items.each do |li|
        expect(GravityService).to receive(:deduct_inventory).with(li)
      end
      service.send(:deduct_inventory)
      expect(service.instance_variable_get('@deducted_inventory').count).to eq line_items.count
    end
  end

  describe '#post_process!' do
    before do
      service.instance_variable_set('@transaction', transaction)
    end
    it 'updates the external_charge_id on the order with the external_id of the transaction' do
      service.send(:post_process!)
      expect(order.reload.external_charge_id).to eq transaction.external_id
    end

    it 'records the order action in DataDog' do
      expect(Exchange).to receive_message_chain(:dogstatsd, :increment).with('order.submit')
      service.send(:post_process!)
    end
  end

  describe '#handle_transaction' do
    context 'with a transaction present' do
      before do
        ActiveJob::Base.queue_adapter = :test
      end
      it "adds the transaction to the order's transaction list" do
        service.instance_variable_set('@transaction', transaction)
        expect { service.send(:handle_transaction) }.to change(order.transactions, :count).by(1)
      end
      context 'with a failed transaction' do
        it 'sends a notification about the failed charge' do
          service.instance_variable_set('@transaction', failed_transaction)
          service.send(:handle_transaction)
          expect(PostTransactionNotificationJob).to have_been_enqueued.with(failed_transaction.id, TransactionEvent::CREATED, user_id)
        end
      end
    end
    context 'without a transaction' do
      it 'does nothing' do
        service.instance_variable_set('@transaction', nil)
        expect { service.send(:handle_transaction) }.not_to change(order.transactions, :count)
        expect(PostTransactionNotificationJob).not_to have_been_enqueued
      end
    end
  end

  describe '#undeduct_inventory' do
    it 'undeducts deducted inventory' do
      service.instance_variable_set('@deducted_inventory', line_items)
      line_items.each do |li|
        expect(GravityService).to receive(:undeduct_inventory).with(li)
      end
      service.send(:undeduct_inventory)
    end
  end

  describe '#validate_credit_card!' do
    it 'raises an error if the credit card does not have an external id' do
      allow(GravityService).to receive(:get_credit_card).and_return(id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: nil)
      expect { service.send(:validate_credit_card!) }.to raise_error do |error|
        expect(error).to be_a(Errors::ValidationError)
        expect(error.code).to eq :credit_card_missing_external_id
        expect(error.data).to match(credit_card_id: 'cc-1')
      end
    end

    it 'raises an error if the credit card does not have a customer account' do
      allow(GravityService).to receive(:get_credit_card).and_return(id: 'cc-1', external_id: 'cc-1')
      expect { service.send(:validate_credit_card!) }.to raise_error do |error|
        expect(error).to be_a(Errors::ValidationError)
        expect(error.code).to eq :credit_card_missing_customer
        expect(error.data).to match(credit_card_id: 'cc-1')
      end
    end

    it 'raises an error if the credit card does not have a customer account external id' do
      allow(GravityService).to receive(:get_credit_card).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { some_prop: 'some_val' }, deactivated_at: nil)
      expect { service.send(:validate_credit_card!) }.to raise_error do |error|
        expect(error).to be_a(Errors::ValidationError)
        expect(error.code).to eq :credit_card_missing_customer
        expect(error.data).to match(credit_card_id: 'cc-1')
      end
    end

    it 'raises an error if the card is deactivated' do
      allow(GravityService).to receive(:get_credit_card).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: 2.days.ago)
      expect { service.send(:validate_credit_card!) }.to raise_error do |error|
        expect(error).to be_a(Errors::ValidationError)
        expect(error.code).to eq :credit_card_deactivated
        expect(error.data).to match(credit_card_id: 'cc-1')
      end
    end
  end
end
