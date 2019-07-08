require 'stripe_mock'

RSpec.shared_context 'use stripe mock' do
  let(:stripe_helper) { StripeMock.create_test_helper }
  before { StripeMock.start }
  after { StripeMock.stop }
  let(:stripe_customer) do
    Stripe::Customer.create(
      email: 'someuser@email.com',
      source: stripe_helper.generate_card_token
    )
  end
  let(:uncaptured_charge) do
    card_token = stripe_helper.generate_card_token
    Stripe::Charge.create(
      amount: 22_222,
      currency: 'usd',
      source: card_token,
      payment_method: card_token,
      destination: 'ma-1',
      capture: false
    )
  end
  let(:buyer_amount) { 22_222 }
  let(:seller_amount) { 10_000 }
  let(:captured_charge) do
    card_token = stripe_helper.generate_card_token
    Stripe::Charge.create(
      amount: buyer_amount,
      currency: 'usd',
      source: card_token,
      payment_method: card_token,
      destination: {
        account: 'ma-1',
        amount: seller_amount
      },
      capture: true
    )
  end
end

RSpec.configure do |rspec|
  rspec.include_context 'use stripe mock', include_shared: true
end
