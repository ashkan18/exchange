require 'rails_helper'
require 'support/gravity_helper'

describe CreateOfferOrderService, type: :services do
  describe '#process!' do
    let(:user_id) { 'user-id' }
    let(:artwork) { gravity_v1_artwork }
    context 'known artwork' do
      before do
        expect(Adapters::GravityV1).to receive(:get).and_return(artwork)
      end
      context 'without edition set' do
        let(:artwork) { gravity_v1_artwork(edition_sets: nil) }
        let(:service) { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'artwork-id', edition_set_id: nil, quantity: 2) }
        it 'create order with proper data' do
          expect do
            service.process!
            order = service.order
            expect(order.currency_code).to eq 'USD'
            expect(order.buyer_id).to eq user_id
            expect(order.seller_id).to eq 'gravity-partner-id'
            expect(order.line_items.count).to eq 1
            expect(order.line_items.first.price_cents).to eq 5400_12
            expect(order.line_items.first.artwork_id).to eq 'artwork-id'
            expect(order.line_items.first.artwork_version_id).to eq 'current-version-id'
            expect(order.line_items.first.edition_set_id).to be_nil
            expect(order.line_items.first.quantity).to eq 2
            expect(order.items_total_cents).to eq 0
            expect(order.mode).to eq Order::OFFER
          end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
        end
        it 'sets state_expires_at for newly pending order' do
          Timecop.freeze(Time.now.beginning_of_day) do
            service.process!
            order = service.order
            expect(order.state).to eq Order::PENDING
            expect(order.state_updated_at).to eq Time.now.beginning_of_day
            expect(order.state_expires_at).to eq 2.days.from_now
          end
        end
      end

      context 'artwork with one edition set' do
        let(:artwork) { gravity_v1_artwork }
        context 'with passing edition_set_id' do
          let(:service) { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'artwork-id', edition_set_id: 'edition-set-id', quantity: 2) }
          it 'creates order' do
            expect do
              service.process!
              order = service.order
              expect(order.currency_code).to eq 'USD'
              expect(order.buyer_id).to eq user_id
              expect(order.seller_id).to eq 'gravity-partner-id'
              expect(order.line_items.count).to eq 1
              expect(order.line_items.first.price_cents).to eq 4200_42
              expect(order.line_items.first.artwork_id).to eq 'artwork-id'
              expect(order.line_items.first.artwork_version_id).to eq 'current-version-id'
              expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
              expect(order.line_items.first.quantity).to eq 2
              job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
              expect(job).to_not be_nil
              expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
              expect(job[:args][0]).to eq order.id
              expect(job[:args][1]).to eq Order::PENDING
            end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
          end
        end
        context 'without passing edition_set_id' do
          let(:service) { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'artwork-id', quantity: 2) }
          it 'creates order with artworks edition set' do
            expect do
              service.process!
              order = service.order
              expect(order.currency_code).to eq 'USD'
              expect(order.buyer_id).to eq user_id
              expect(order.seller_id).to eq 'gravity-partner-id'
              expect(order.line_items.count).to eq 1
              expect(order.line_items.first.price_cents).to eq 4200_42
              expect(order.line_items.first.artwork_id).to eq 'artwork-id'
              expect(order.line_items.first.artwork_version_id).to eq 'current-version-id'
              expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
              expect(order.line_items.first.quantity).to eq 2
              job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
              expect(job).to_not be_nil
              expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
              expect(job[:args][0]).to eq order.id
              expect(job[:args][1]).to eq Order::PENDING
            end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
          end
        end
      end

      context 'artwork with multiple edition sets' do
        let(:edition_sets) do
          [{
            id: 'edition-set-id',
            forsale: true,
            sold: false,
            price: '$4200',
            price_listed: 4200.42,
            price_currency: 'USD',
            acquireable: false,
            dimensions: { in: '44 × 30 1/2 in', cm: '111.8 × 77.5 cm' },
            editions: 'Edition of 15',
            display_price_currency: 'USD (United States Dollar)',
            availability: 'for sale'
          }, {
            id: 'edition-set-id2',
            forsale: true,
            sold: false,
            price: '$4400',
            price_listed: 4200.42,
            price_currency: 'USD',
            acquireable: false,
            dimensions: { in: '44 × 30 1/2 in', cm: '111.8 × 77.5 cm' },
            editions: 'Edition of 15',
            display_price_currency: 'USD (United States Dollar)',
            availability: 'for sale'
          }]
        end
        let(:artwork) { gravity_v1_artwork(edition_sets: edition_sets) }
        context 'without passing edition set' do
          let(:service) { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'artwork-id', quantity: 2) }
          it 'raises error' do
            expect do
              service.process!
            end.to raise_error do |error|
              expect(error).to be_a Errors::ValidationError
              expect(error.type).to eq :validation
              expect(error.code).to eq :missing_edition_set_id
              expect(error.data).to match(artwork_id: 'artwork-id')
            end
          end
        end
        context 'with passing edition set' do
          let(:service) { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'artwork-id', edition_set_id: 'edition-set-id', quantity: 2) }
          it 'creates order with proper data' do
            expect do
              service.process!
              order = service.order
              expect(order.mode).to eq Order::OFFER
              expect(order.currency_code).to eq 'USD'
              expect(order.buyer_id).to eq user_id
              expect(order.seller_id).to eq 'gravity-partner-id'
              expect(order.line_items.count).to eq 1
              expect(order.line_items.first.price_cents).to eq 4200_42
              expect(order.line_items.first.artwork_id).to eq 'artwork-id'
              expect(order.line_items.first.artwork_version_id).to eq 'current-version-id'
              expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
              expect(order.line_items.first.quantity).to eq 2
              job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
              expect(job).to_not be_nil
              expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
              expect(job[:args][0]).to eq order.id
              expect(job[:args][1]).to eq Order::PENDING
            end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
          end
        end
      end
    end
    context 'with unknown artwork' do
      before do
        expect(Adapters::GravityV1).to receive(:get).and_raise(Adapters::GravityError.new('unknown artwork'))
      end
      it 'raises error' do
        expect { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'random-artwork', quantity: 2).process! }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :unknown_artwork
          expect(error.type).to eq :validation
        end
      end
    end
    context 'with unpublished artwork' do
      before do
        expect(Adapters::GravityV1).to receive(:get).and_return(gravity_v1_artwork(published: false))
      end
      it 'raises error' do
        expect { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'random-artwork', quantity: 2).process! }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :unpublished_artwork
          expect(error.type).to eq :validation
        end
      end
    end
    context 'with disabled ecommerce artwork' do
      before do
        expect(Adapters::GravityV1).to receive(:get).and_return(gravity_v1_artwork(offerable: false))
      end
      it 'raises error' do
        expect { CreateOfferOrderService.new(user_id: user_id, artwork_id: 'random-artwork', quantity: 2).process! }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :not_offerable
          expect(error.type).to eq :validation
        end
      end
    end
  end
end
