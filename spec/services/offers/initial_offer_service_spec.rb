require 'rails_helper'

describe Offers::InitialOfferService, type: :services do
  describe '#process!' do
    let(:user_id) { 'user-id' }
    let(:amount_cents) { 200 }
    let(:mode) { Order::OFFER }
    let(:state) { Order::PENDING }
    let(:state_reason) { nil }
    let(:order) { Fabricate(:order, seller_id: user_id, seller_type: Order::USER, state: state, state_reason: state_reason, mode: mode) }
    let(:service) { Offers::InitialOfferService.new(order, amount_cents, user_id) }
    context 'Buy Order' do
      let(:mode) { Order::BUY }
      it 'raises error' do
        expect { service.process! }.to raise_error do |e|
          expect(e.type).to eq :validation
          expect(e.code).to eq :cant_offer
        end
      end
    end
    Order::STATES.reject { |s| [Order::PENDING, Order::CANCELED].include? s }.each do |state|
      context "order in #{state}" do
        let(:state) { state }
        it 'raises error' do
          expect { service.process! }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :cant_offer
          end
        end
      end
    end
    context 'Canceled order' do
      let(:state) { Order::CANCELED }
      let(:state_reason) { 'seller_lapsed' }
      it 'raises error' do
        expect { service.process! }.to raise_error do |e|
          expect(e.type).to eq :validation
          expect(e.code).to eq :cant_offer
        end
      end
    end
    context 'Pending Order' do
      let(:state) { Order::PENDING }
      it 'creates offer' do
        expect { service.process! }.to change(order.offers, :count).by(1)
        offer = order.offers.first
        expect(offer.amount_cents).to eq 200
        expect(offer.from_id).to eq user_id
        expect(offer.from_type).to eq Order::USER
        expect(offer.creator_id).to eq user_id
        expect(order.reload.state).to eq state
        expect(order.last_offer).to eq offer
        expect(order.items_total_cents).to eq 200
      end
    end
  end
end
