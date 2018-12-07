require 'rails_helper'

describe Offers::RejectOfferService, type: :services do
  describe '#process!' do
    let!(:order) { Fabricate(:order, state: Order::SUBMITTED) }
    let!(:offer) { Fabricate(:offer, order: order) }
    let(:service) { Offers::RejectOfferService.new(offer: offer, reject_reason: Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low]) }

    before do
      # last_offer is set in Orders::InitialOffer. "Stubbing" out the
      # dependent behavior of this class to by setting last_offer directly
      order.update!(last_offer: offer)
    end

    context 'with a submitted offer' do
      it 'updates the state of the order' do
        expect do
          service.process!
        end.to change { order.state }.from(Order::SUBMITTED).to(Order::CANCELED)
                                     .and change { order.state_reason }
          .from(nil).to(Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low])
      end

      it 'instruments an rejected offer' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('offer.reject')

        service.process!

        expect(dd_statsd).to have_received(:increment).with('offer.reject')
      end
    end

    context "when we can't reject the order" do
      let(:order) { Fabricate(:order, state: Order::PENDING) }
      let(:offer) { Fabricate(:offer, order: order) }

      it "doesn't instrument" do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('offer.reject')

        expect { service.process! }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end
    end

    context 'attempting to reject not the last offer' do
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

      it 'does not reject the order' do
        expect {  service.process! }.to raise_error(Errors::ValidationError)

        expect(order.reload.state).to eq(Order::SUBMITTED)
      end

      it 'does not instrument' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.reject')

        expect {  service.process! }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end
    end
  end

  def stub_ddstatsd_instance
    dd_statsd = double(Datadog::Statsd)
    allow(Exchange).to receive(:dogstatsd).and_return(dd_statsd)

    dd_statsd
  end
end
