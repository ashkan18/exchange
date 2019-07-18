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

  describe '#hold_charge' do
    it "creates a payment_intent using user's credit card and amount and stores it" do
      transaction = PaymentService.hold_charge(params)
      expect(transaction).to have_attributes(
        amount_cents: 20_00,
        source_id: stripe_customer.default_source,
        destination_id: 'ma-1',
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        transaction_type: Transaction::HOLD,
        status: Transaction::SUCCESS,
        external_type: Transaction::PAYMENT_INTENT
      )
    end
    it 'returns transaction in REQUIRES_ACTION state when payment intent couldnt be confirmed' do
      transaction = PaymentService.hold_charge(params.merge(buyer_amount: 3184))
      expect(transaction).to have_attributes(
        amount_cents: 3184,
        source_id: stripe_customer.default_source,
        destination_id: 'ma-1',
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        transaction_type: Transaction::HOLD,
        status: Transaction::REQUIRES_ACTION,
        external_type: Transaction::PAYMENT_INTENT
      )
    end
  end

  describe '#capture_authorized_charge' do
    it 'captures a charge' do
      @hold_transaction = Fabricate(:transaction, external_id: payment_intent.id, external_type: Transaction::PAYMENT_INTENT)
      transaction = PaymentService.capture_authorized_charge(payment_intent.id)
      expect(transaction).to have_attributes(amount_cents: payment_intent.amount, transaction_type: Transaction::CAPTURE, source_id: payment_intent.payment_method, status: Transaction::SUCCESS)
    end
    it 'catches Stripe errors and returns a failed transaction' do
      Fabricate(:transaction, external_id: requires_payment_method_payment_intent.id, external_type: Transaction::PAYMENT_INTENT)
      allow_any_instance_of(Stripe::PaymentIntent).to receive(:capture)
      transaction = PaymentService.capture_authorized_charge(requires_payment_method_payment_intent.id)
      expect(transaction).to have_attributes(
        external_id: requires_payment_method_payment_intent.id,
        failure_code: 'card_declined',
        failure_message: 'Not enough funds.',
        decline_code: 'insufficient_funds',
        transaction_type: Transaction::CAPTURE,
        status: Transaction::FAILURE
      )
    end
  end

  describe '#refund_charge' do
    it 'refunds a charge for the full amount' do
      Fabricate(:transaction, external_id: payment_intent.id, external_type: Transaction::PAYMENT_INTENT)
      transaction = PaymentService.refund_charge(payment_intent.id)
      expect(transaction.external_id).to match(/test_re/i)
      expect(transaction.transaction_type).to eq Transaction::REFUND
      expect(transaction.status).to eq Transaction::SUCCESS
    end
    it 'catches Stripe errors and returns a failed transaction' do
      Fabricate(:transaction, external_id: payment_intent.id, external_type: Transaction::PAYMENT_INTENT)
      StripeMock.prepare_card_error(:processing_error, :new_refund)
      transaction = PaymentService.refund_charge(payment_intent.id)
      expect(transaction.external_id).to eq payment_intent.id
      expect(transaction.failure_code).to eq 'processing_error'
      expect(transaction.failure_message).to eq 'An error occurred while processing the card'
      expect(transaction.transaction_type).to eq Transaction::REFUND
      expect(transaction.status).to eq Transaction::FAILURE
    end
  end
end
