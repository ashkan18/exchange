require 'rails_helper'
require 'support/gravity_helper'
require 'support/use_stripe_mock'

describe PaymentService, type: :services do
  include_context 'use stripe mock'

  let(:currency_code) { 'usd' }
  let(:buyer_amount) { 20_00 }
  let(:seller_amount) { 10_00 }
  let(:credit_card) { { external_id: stripe_customer.default_source, customer_account: { external_id: stripe_customer.id } } }
  let(:merchant_account) { { external_id: 'ma-1' } }
  let(:params) do
    {
      buyer_amount: buyer_amount,
      credit_card: credit_card,
      currency_code: currency_code,
      description: 'Gallery via Artsy',
      merchant_account: merchant_account,
      metadata: { this: 'is', a: 'test' },
      seller_amount: seller_amount
    }
  end

  describe '#create_and_authorize_charge' do
    it "authorizes a charge on the user's credit card" do
      transaction = PaymentService.create_and_authorize_charge(params)
      expect(transaction.amount_cents).to eq(20_00)
      expect(transaction.source_id).to eq(stripe_customer.default_source)
      expect(transaction.status).to eq(Transaction::SUCCESS)
      expect(transaction.transaction_type).to eq Transaction::HOLD
      expect(transaction.failure_code).to be_nil
      expect(transaction.failure_message).to be_nil
      expect(transaction.decline_code).to be_nil
    end
    it 'catches Stripe errors and returns a failed transaction' do
      StripeMock.prepare_card_error(:card_declined, :new_charge)
      transaction = PaymentService.create_and_authorize_charge(params)
      expect(transaction.amount_cents).to eq buyer_amount
      expect(transaction.source_id).to eq stripe_customer.default_source
      expect(transaction.destination_id).to eq 'ma-1'
      expect(transaction.failure_code).to eq 'card_declined'
      expect(transaction.failure_message).to eq 'The card was declined'
      expect(transaction.decline_code).to eq 'do_not_honor'
      expect(transaction.transaction_type).to eq Transaction::HOLD
      expect(transaction.status).to eq Transaction::FAILURE
    end
  end

  describe '#capture_authorized_charge' do
    it 'captures a charge' do
      transaction = PaymentService.capture_authorized_charge(uncaptured_charge.id)
      expect(transaction.amount_cents).to eq(uncaptured_charge.amount)
      expect(transaction.transaction_type).to eq Transaction::CAPTURE
      expect(transaction.source_id).to eq 'test_tok_1'
      expect(transaction.status).to eq Transaction::SUCCESS
    end
    it 'catches Stripe errors and returns a failed transaction' do
      StripeMock.prepare_card_error(:card_declined, :capture_charge)
      transaction = PaymentService.capture_authorized_charge(uncaptured_charge.id)
      expect(transaction.external_id).to eq uncaptured_charge.id
      expect(transaction.failure_code).to eq 'card_declined'
      expect(transaction.failure_message).to eq 'The card was declined'
      expect(transaction.decline_code).to eq 'do_not_honor'
      expect(transaction.transaction_type).to eq Transaction::CAPTURE
      expect(transaction.status).to eq Transaction::FAILURE
    end
  end

  describe '#refund_charge' do
    it 'refunds a charge for the full amount' do
      transaction = PaymentService.refund_charge(captured_charge.id)
      expect(transaction.external_id).to match(/test_re/i)
      expect(transaction.transaction_type).to eq Transaction::REFUND
      expect(transaction.status).to eq Transaction::SUCCESS
    end
    it 'catches Stripe errors and returns a failed transaction' do
      StripeMock.prepare_card_error(:processing_error, :new_refund)
      transaction = PaymentService.refund_charge(captured_charge.id)
      expect(transaction.external_id).to eq captured_charge.id
      expect(transaction.failure_code).to eq 'processing_error'
      expect(transaction.failure_message).to eq 'An error occurred while processing the card'
      expect(transaction.transaction_type).to eq Transaction::REFUND
      expect(transaction.status).to eq Transaction::FAILURE
    end
  end
end
