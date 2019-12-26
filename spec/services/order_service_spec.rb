require 'rails_helper'
require 'support/gravity_helper'

describe OrderService, type: :services do
  include_context 'use stripe mock'
  include_context 'include stripe helper'
  let(:state) { Order::PENDING }
  let(:state_reason) { state == Order::CANCELED ? 'seller_lapsed' : nil }
  let(:order) { Fabricate(:order, external_charge_id: captured_charge.id, state: state, state_reason: state_reason, buyer_id: 'b123') }
  let!(:line_items) { [Fabricate(:line_item, order: order, artwork_id: 'a-1', list_price_cents: 123_00), Fabricate(:line_item, order: order, artwork_id: 'a-2', edition_set_id: 'es-1', quantity: 2, list_price_cents: 124_00)] }
  let(:user_id) { 'user-id' }

  describe 'set_payment!' do
    let(:credit_card_id) { 'gravity-cc-1' }
    context 'order in pending state' do
      let(:state) { Order::PENDING }

      context "with a credit card id for the buyer's credit card" do
        let(:credit_card) { { id: credit_card_id, user: { _id: 'b123' } } }

        it 'sets credit_card_id on the order' do
          expect(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
          OrderService.set_payment!(order, credit_card_id)
          expect(order.reload.credit_card_id).to eq 'gravity-cc-1'
        end
      end

      context 'with a credit card id for credit card not belonging to the buyer' do
        let(:invalid_credit_card) { { id: credit_card_id, user: { _id: 'b456' } } }

        it 'raises an error' do
          expect(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(invalid_credit_card)
          expect { OrderService.set_payment!(order, credit_card_id) }.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.code).to eq :invalid_credit_card
          end
        end
      end
    end
  end

  describe 'fulfill_at_once!' do
    let(:fulfillment_params) { { courier: 'usps', tracking_id: 'track_this_id', estimated_delivery: 10.days.from_now } }

    context 'with order in approved state' do
      let(:state) { Order::APPROVED }

      it 'changes order state to fulfilled' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        expect(order.reload.state).to eq Order::FULFILLED
      end

      it 'creates one fulfillment model' do
        Timecop.freeze do
          expect { OrderService.fulfill_at_once!(order, fulfillment_params, user_id) }.to change(Fulfillment, :count).by(1)
          fulfillment = Fulfillment.last
          expect(fulfillment.courier).to eq 'usps'
          expect(fulfillment.tracking_id).to eq 'track_this_id'
          expect(fulfillment.estimated_delivery.to_date).to eq 10.days.from_now.to_date
        end
      end

      it 'sets all line items fulfillment to one fulfillment' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        fulfillment = Fulfillment.last
        line_items.each do |li|
          expect(li.fulfillments.first.id).to eq fulfillment.id
        end
      end

      it 'queues job to post fulfillment event' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        expect(PostEventJob).to have_been_enqueued.with('commerce', kind_of(String), 'order.fulfilled')
      end
    end

    Order::STATES.reject { |s| s == Order::APPROVED }.each do |state|
      context "order in #{state}" do
        let(:state) { state }
        it 'raises error' do
          expect do
            OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
          end.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.code).to eq :invalid_state
          end
        end

        it 'does not add fulfillments' do
          expect do
            OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
          end.to raise_error(Errors::ValidationError).and change(Fulfillment, :count).by(0)
        end
      end
    end
  end

  describe 'abandon!' do
    context 'order in pending state' do
      let(:state) { Order::PENDING }
      it 'abandons the order' do
        OrderService.abandon!(order)
        expect(order.reload.state).to eq Order::ABANDONED
      end

      it 'updates state_update_at' do
        Timecop.freeze do
          order.update!(state_updated_at: 10.days.ago)
          OrderService.abandon!(order)
          expect(order.reload.state_updated_at.to_date).to eq Time.now.utc.to_date
        end
      end

      it 'creates state history' do
        expect { OrderService.abandon!(order) }.to change(order.state_histories, :count).by(1)
      end
    end

    Order::STATES.reject { |s| s == Order::PENDING }.each do |state|
      context "order in #{state}" do
        let(:state) { state }
        it 'does not change state' do
          expect { OrderService.abandon!(order) }.to raise_error(Errors::ValidationError)
          expect(order.reload.state).to eq state
        end

        it 'raises error' do
          expect { OrderService.abandon!(order) }.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.type).to eq :validation
            expect(error.code).to eq :invalid_state
            expect(error.data).to match(state: state)
          end
        end
      end
    end
  end

  describe 'approve!' do
    let(:state) { Order::SUBMITTED }
    context 'buy now, capture payment_intent' do
      it 'raises error when approving wire transfer orders' do
        order.update!(payment_method: Order::WIRE_TRANSFER)
        expect { OrderService.approve!(order, user_id) }.to raise_error do |e|
          expect(e.code).to eq :unsupported_payment_method
        end
      end

      context 'failed stripe capture' do
        before do
          prepare_payment_intent_capture_failure(charge_error: { code: 'card_declined', decline_code: 'do_not_honor', message: 'The card was declined' })
        end
        it 'adds failed transaction and stays in submitted state' do
          expect { OrderService.approve!(order, user_id) }.to raise_error(Errors::ProcessingError).and change(order.transactions, :count).by(1)
          transaction = order.transactions.order(created_at: :desc).first
          expect(transaction).to have_attributes(
            status: Transaction::FAILURE,
            failure_code: 'card_declined',
            failure_message: 'Your card was declined.',
            decline_code: 'do_not_honor',
            external_id: 'pi_1',
            external_type: Transaction::PAYMENT_INTENT
          )
          expect(order.reload.state).to eq Order::SUBMITTED
          expect(OrderEvent).not_to receive(:delay_post)
          expect(OrderFollowUpJob).not_to receive(:set)
          expect(RecordSalesTaxJob).not_to receive(:perform_later)
        end
      end

      context 'with failed post_process' do
        it 'is in approved state' do
          prepare_payment_intent_capture_success
          allow(OrderEvent).to receive(:delay_post).and_raise('Perform what later?!')
          expect { OrderService.approve!(order, user_id) }.to raise_error(RuntimeError).and change(order.transactions, :count).by(1)
          expect(order.reload.state).to eq Order::APPROVED
        end
      end

      context 'with successful approval' do
        before do
          prepare_payment_intent_capture_success
          ActiveJob::Base.queue_adapter = :test
          expect { OrderService.approve!(order, user_id) }.to change(order.transactions, :count).by(1)
        end
        it 'adds successful transaction, updates the state and queues expected jobs' do
          expect(order.transactions.order(created_at: :desc).first).to have_attributes(
            status: Transaction::SUCCESS,
            external_id: 'pi_1',
            external_type: Transaction::PAYMENT_INTENT
          )
          expect(order.state).to eq Order::APPROVED
          expect(PostEventJob).to have_been_enqueued.with('commerce', kind_of(String), 'order.approved')
          expect(OrderFollowUpJob).to have_been_enqueued.with(order.id, Order::APPROVED)
          line_items.each { |li| expect(RecordSalesTaxJob).to have_been_enqueued.with(li.id) }
        end
      end
    end
  end
end
