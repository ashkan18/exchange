require 'rails_helper'

describe Offers::AddPendingCounterOfferService, type: :services do
  describe '#process!' do
    let(:offer_from_id) { 'user-id' }
    let(:offer_from_type) { Order::PARTNER }
    let(:order) { Fabricate(:order, state: Order::SUBMITTED) }
    let(:offer) { Fabricate(:offer, order: order, amount_cents: 10000, submitted_at: 1.day.ago) }
    let(:service) { Offers::AddPendingCounterOfferService.new(offer: offer, amount_cents: 20000, from_id: offer_from_id, from_type: offer_from_type) }
    let(:offer_totol_updater_service) { double }

    before do
      # last_offer is set in Orders::InitialOffer. "Stubbing" out the
      # dependent behavior of this class to by setting last_offer directly
      order.update!(last_offer: offer)
    end

    context 'with a submitted offer' do
      before do
        expect(Offers::OfferTotalUpdaterService).to receive(:new).with(offer: instance_of(Offer)).and_return(offer_totol_updater_service)
        expect(offer_totol_updater_service).to receive(:process!).and_return(instance_of(offer))
      end
      it 'adds a new offer to order and does not updates last offer' do
        service.process!
        expect(order.offers.count).to eq(2)
        pending_offer = order.offers.reject { |offer| offer.id == order.last_offer.id }.first
        expect(pending_offer.amount_cents).to eq(20000)
        expect(pending_offer.responds_to).to eq(offer)
        expect(pending_offer.from_id).to eq(offer_from_id)
        expect(pending_offer.from_type).to eq(offer_from_type)
        expect(pending_offer.submitted_at).to be_nil
      end
    end

    context 'attempting to counter not the last offer' do
      let!(:another_offer) { Fabricate(:offer, order: order) }

      before do
        # last_offer is set in Orders::InitialOffer. "Stubbing" out the
        # dependent behavior of this class to by setting last_offer directly
        order.update!(last_offer: another_offer)
      end

      it 'raises a validation error' do
        expect {  service.process! }
          .to raise_error(Errors::ValidationError)
      end

      it 'does not change order and offers' do
        expect {  service.process! }.to raise_error(Errors::ValidationError)

        expect(order.reload.state).to eq(Order::SUBMITTED)
        expect(order.reload.offers.count).to eq(2)
      end
    end

    context 'attempting to counter its own offer' do
      let!(:offer) { Fabricate(:offer, order: order, from_type: Order::PARTNER) }

      it 'raises a validation error' do
        expect {  service.process! }
          .to raise_error(Errors::ValidationError)
      end

      it 'does not change order and offers' do
        expect {  service.process! }.to raise_error(Errors::ValidationError)

        expect(order.reload.state).to eq(Order::SUBMITTED)
        expect(order.reload.offers.count).to eq(1)
      end
    end
  end

  def stub_ddstatsd_instance
    dd_statsd = double(Datadog::Statsd)
    allow(Exchange).to receive(:dogstatsd).and_return(dd_statsd)

    dd_statsd
  end
end
