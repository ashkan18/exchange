require 'rails_helper'
require 'support/gravity_helper'

describe Handlers::OrderCreator, type: :services do
  let(:gravity_artwork) { gravity_v1_artwork }
  let(:artwork_id) { 'artwork-id' }
  let(:edition_set_id) { nil }
  let(:order_mode) { Order::BUY }
  let(:event) { double(data: { buyer_id: 'user1', buyer_type: Order::USER, mode: order_mode, quantity: 1, artwork_id: artwork_id, edition_set_id: edition_set_id}, metadata: { user_agent: '007', user_ip: '0.0.7' })}
  let(:order_creator) { Handlers::OrderCreator.new.call(event) }
  before do
    allow(Adapters::GravityV1).to receive(:get).with("/artwork/#{artwork_id}").once.and_return(gravity_artwork)
  end
  describe '#valid?' do
    context 'unknown artwork' do
      let(:gravity_artwork) { nil }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:unknown_artwork]
      end
    end
    context 'unpublished artwork' do
      let(:gravity_artwork) { gravity_v1_artwork(published: false) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:unpublished_artwork]
      end
    end
    context 'unknown edition_set_id' do
      let(:edition_set_id) { 'some-random-id' }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:unknown_edition_set]
      end
    end
    context 'missing required edition_set_id with artwork with many edition sets' do
      let(:gravity_artwork) { gravity_v1_artwork(edition_sets: [{ id: 'ed1' }, { id: 2 }]) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:missing_edition_set_id]
      end
    end
    context 'invalid action' do
      context 'offer order' do
        let(:order_mode) { Order::OFFER }
        let(:gravity_artwork) { gravity_v1_artwork(offerable: false) }
        before do
          expect(order_creator.valid?).to eq false
        end
        it 'sets correct error' do
          expect(order_creator.errors).to eq [:not_offerable]
        end
      end
      context 'Buy order' do
        let(:order_mode) { Order::BUY }
        let(:gravity_artwork) { gravity_v1_artwork(acquireable: false) }
        before do
          expect(order_creator.valid?).to eq false
        end
        it 'sets correct error' do
          expect(order_creator.errors).to eq [:not_acquireable]
        end
      end
    end
    context 'artwork without price' do
      let(:gravity_artwork) { gravity_v1_artwork(price_listed: nil, edition_sets: []) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:missing_price]
      end
    end
    context 'artwork without currency' do
      let(:gravity_artwork) { gravity_v1_artwork(price_currency: nil, edition_sets: []) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:missing_currency]
      end
    end
    context 'editionset missing price' do
      let(:gravity_artwork) { gravity_v1_artwork(price_listed: nil, edition_sets: [{ id: 'edition-set-id' }]) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:missing_price]
      end
    end
    context 'editionset missing currency' do
      let(:gravity_artwork) { gravity_v1_artwork(price_listed: nil, edition_sets: [{ id: 'edition-set-id', price_listed: 420, price_currency: nil }]) }
      before do
        expect(order_creator.valid?).to eq false
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq [:missing_currency]
      end
    end
    context 'valid artwork' do
      before do
        expect(order_creator.valid?).to eq true
      end
      it 'sets correct error' do
        expect(order_creator.errors).to eq []
      end
    end
  end

  describe '#create!' do
    context 'invalid artwork' do
      let(:gravity_artwork) { nil }
      it 'raises error' do
        expect { order_creator.create! }.to raise_error do |e|
          expect(e.type).to eq :validation
          expect(e.code).to eq :unknown_artwork
          expect(Order.count).to eq 0
          expect(LineItem.count).to eq 0
        end
      end
    end
    context 'artwork with one editionset' do
      before do
        expect do
          @order = order_creator.create!
        end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
      end
      it 'creates the order with expected fields' do
        expect(@order.mode).to eq order_mode
        expect(@order.buyer_id).to eq 'user1'
        expect(@order.buyer_type).to eq Order::USER
        expect(@order.seller_id).to eq 'gravity-partner-id'
        expect(@order.seller_type).to eq 'gallery'
        expect(@order.currency_code).to eq 'USD'
        expect(@order.state).to eq Order::PENDING
        expect(@order.state_expires_at).not_to be_nil
        expect(@order.original_user_agent).to eq '007'
        expect(@order.original_user_ip).to eq '0.0.7'
      end
      it 'sets items total cents on the order to edition set price' do
        expect(@order.items_total_cents).to eq 420042
      end
      it 'creates correct line item with edition set id' do
        expect(@order.line_items.count).to eq 1
        line_item = @order.line_items.first
        expect(line_item.artwork_id).to eq artwork_id
        expect(line_item.edition_set_id).to eq 'edition-set-id'
        expect(line_item.list_price_cents).to eq 420042
        expect(line_item.quantity).to eq 1
      end
    end
    context 'artwork without editionset' do
      let(:gravity_artwork) { gravity_v1_artwork(edition_sets: []) }
      before do
        expect do
          @order = order_creator.create!
        end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
      end
      it 'creates the order with expected fields' do
        expect(@order.mode).to eq order_mode
        expect(@order.buyer_id).to eq 'user1'
        expect(@order.buyer_type).to eq Order::USER
        expect(@order.seller_id).to eq 'gravity-partner-id'
        expect(@order.seller_type).to eq 'gallery'
        expect(@order.currency_code).to eq 'USD'
        expect(@order.state).to eq Order::PENDING
        expect(@order.state_expires_at).not_to be_nil
        expect(@order.original_user_agent).to eq '007'
        expect(@order.original_user_ip).to eq '0.0.7'
      end
      it 'sets items total cents on the order to edition set price' do
        expect(@order.items_total_cents).to eq 540012
      end
      it 'creates correct line item' do
        expect(@order.line_items.count).to eq 1
        line_item = @order.line_items.first
        expect(line_item.artwork_id).to eq artwork_id
        expect(line_item.edition_set_id).to be_nil
        expect(line_item.list_price_cents).to eq 540012
        expect(line_item.quantity).to eq 1
      end
    end
    context 'with block' do
      it 'creates order and calls the block' do
        block_method = double(call: nil)
        expect do
          expect(block_method).to receive(:call).with(an_instance_of(Order))
          order_creator.create! do |order|
            block_method.call(order)
          end
        end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
      end
    end
  end

  describe '#find_or_create!' do
    let(:order_state) { Order::PENDING }
    let(:existing_order) { Fabricate(:order, buyer_id: 'user1', buyer_type: Order::USER, state: order_state, mode: order_mode) }
    let(:edition_set_id) { 'edition-set-id' }
    let!(:line_item) { Fabricate(:line_item, order: existing_order, artwork_id: 'artwork-id', edition_set_id: edition_set_id) }
    context 'with existing order in pending state with same mode' do
      it 'returns existing order' do
        expect do
          order = order_creator.find_or_create!
          expect(order.id).to eq existing_order.id
        end.not_to change(Order, :count)
      end
      it 'does not call the block' do
        block_method = double(call: nil)
        expect(block_method).not_to receive(:call)
        order_creator.find_or_create! do |order|
          block_method.call(order)
        end
      end
    end
    context 'with existing order in submitted state with same mode' do
      let(:order_state) { Order::SUBMITTED }
      it 'returns existing order' do
        expect do
          order = order_creator.find_or_create!
          expect(order.id).to eq existing_order.id
        end.not_to change(Order, :count)
      end
      it 'does not call the block' do
        block_method = double(call: nil)
        expect(block_method).not_to receive(:call)
        order_creator.find_or_create! do |order|
          block_method.call(order)
        end
      end
    end
    context 'with existing order in pending state in different mode' do
      let(:existing_order) { Fabricate(:order, buyer_id: 'user1', buyer_type: Order::USER, state: order_state, mode: Order::OFFER) }
      it 'creates new Buy order' do
        expect do
          order = order_creator.find_or_create!
          expect(order.id).not_to eq existing_order.id
          expect(order.mode).to eq Order::BUY
        end.to change(Order, :count).by(1)
      end
    end
    [Order::APPROVED, Order::FULFILLED, Order::REFUNDED, Order::ABANDONED].each do |state|
      context "with existing order in #{state}" do
        let(:order_state) { state }
        it 'creates new Buy order' do
          expect do
            order = order_creator.find_or_create!
            expect(order.id).not_to eq existing_order.id
            expect(order.mode).to eq Order::BUY
          end.to change(Order, :count).by(1)
        end
        it 'calls the block' do
          block_method = double(call: nil)
          expect(block_method).to receive(:call)
          order_creator.find_or_create! do |order|
            block_method.call(order)
          end
        end
      end
    end
  end
end
