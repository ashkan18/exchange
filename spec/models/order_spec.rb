require 'rails_helper'

RSpec.describe Order, type: :model do
  let(:order) { Fabricate(:order) }

  it_behaves_like 'a papertrail versioned model', :order

  describe 'validate currency' do
    it 'raises invalid record for unsupported currencies' do
      expect { order.update!(currency_code: 'CAD') }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Currency code is not included in the list')
    end
  end

  describe 'validate payment_method' do
    it 'raises invalid record for unsupported payment_methods' do
      expect do
        order.update!(payment_method: 'blah')
      end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Payment method is not included in the list')
    end

    it 'allows you to create an order with a payment_method set to wire transfer' do
      order.update!(payment_method: Order::WIRE_TRANSFER)
      expect(order.payment_method).to eq('wire transfer')
    end
  end

  describe 'validates state_reason' do
    context 'state requiring reasons' do
      it 'raises error when missing reason for states with required reason' do
        expect do
          order.update!(state: Order::CANCELED)
        end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: State reason Invalid state reason')
      end

      it 'raises error when providing unknown reasons' do
        expect do
          order.update!(state: Order::CANCELED, state_reason: 'random reason')
        end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: State reason Invalid state reason')
      end

      it 'sets state and reason with correct state and reason' do
        order.update!(state: Order::CANCELED, state_reason: Order::REASONS[Order::CANCELED][:seller_lapsed])
        expect(order.reload.state).to eq Order::CANCELED
        expect(order.reload.state_reason).to eq Order::REASONS[Order::CANCELED][:seller_lapsed]
      end

      it 'sets state reason on state history records' do
        order.update!(state: Order::SUBMITTED)
        expect { order.seller_lapse! }.to change(order.state_histories, :count).by(1)
        expect(order.state_histories.last.state).to eq Order::CANCELED
        expect(order.state_histories.last.reason).to eq Order::REASONS[Order::CANCELED][:seller_lapsed]
      end
    end
    context 'state not requiring reason' do
      it 'sets the state' do
        order.update!(state: Order::ABANDONED)
        expect(order.state).to eq Order::ABANDONED
        expect(order.state_reason).to be_nil
      end

      it 'adds proper state history' do
        expect { order.submit! }.to change(order.state_histories, :count).by(1)
        expect(order.reload.state_histories.last.state).to eq Order::SUBMITTED
        expect(order.state_histories.last.reason).to be_nil
      end

      it 'raises error when setting reason' do
        expect do
          order.update!(state: Order::SUBMITTED, state_reason: Order::REASONS[Order::CANCELED][:seller_lapsed])
        end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: State reason Current state not expecting reason: submitted')
      end
    end
  end

  describe 'update_state_timestamps' do
    it 'sets state timestamps in create' do
      expect(order.state_updated_at).not_to be_nil
      expect(order.state_expires_at).to eq order.state_updated_at + 3.days
    end

    it 'does not update timestamps if state did not change' do
      current_timestamp = order.state_updated_at
      order.update!(shipping_total_cents: 12313)
      expect(order.state_updated_at).to eq current_timestamp
    end

    it 'updates timestamps if state changed to state with expiration' do
      current_timestamp = order.state_updated_at
      current_expiration = order.state_expires_at
      order.submit!
      order.save!
      expect(order.state_updated_at).not_to eq current_timestamp
      expect(order.state_expires_at).not_to eq current_expiration
    end

    it 'does not update expiration timestamp if state changed to state without expiration' do
      order.submit!
      order.save!
      submitted_timestamp = order.state_updated_at
      order.reject!
      order.save!
      expect(order.state_updated_at).not_to eq submitted_timestamp
      expect(order.state_expires_at).to be_nil
    end
  end

  describe '#shipping_info' do
    context 'with Ship fulfillment type' do
      it 'returns true when all required shipping data available' do
        order.update!(fulfillment_type: Order::PICKUP, shipping_name: 'Fname Lname', shipping_country: 'IR', shipping_address_line1: 'Vanak', shipping_address_line2: nil, shipping_postal_code: '09821', buyer_phone_number: '0923', shipping_city: 'Tehran')
        expect(order.shipping_info?).to be true
      end

      it 'returns false if missing any shipping data' do
        order.update!(fulfillment_type: Order::SHIP, shipping_name: 'Fname Lname', shipping_country: 'IR', shipping_address_line1: nil, shipping_postal_code: nil, buyer_phone_number: nil)
        expect(order.shipping_info?).to be false
      end
    end

    context 'with Pickup fulfillment type' do
      it 'returns true' do
        order.update!(fulfillment_type: Order::PICKUP, shipping_name: 'Fname Lname', shipping_country: nil, shipping_address_line1: nil, shipping_postal_code: nil, buyer_phone_number: nil)
        expect(order.shipping_info?).to be true
      end
    end
  end

  describe '#update_code' do
    it 'raises an error if it is unable to set a code within specified attempts' do
      expect do
        order.send(:update_code, 0)
      end.to raise_error do |error|
        expect(error).to be_a(Errors::ValidationError)
        expect(error.code).to eq :failed_order_code_generation
      end
    end

    it 'sets a 0-padded 9 digit number for the code on order creation' do
      expect(order.code.length).to eq 9
      expect(order.code).to eq format('%09d', order.code.to_i)
    end
  end

  describe '#create_state_history' do
    context 'when an order is first created' do
      it 'creates a new state history object with its initial state' do
        new_order = Order.create!(state: Order::PENDING, currency_code: 'USD', mode: Order::BUY, payment_method: Order::CREDIT_CARD)
        expect(new_order.state_histories.count).to eq 1
        expect(new_order.state_histories.last.state).to eq Order::PENDING
        expect(new_order.state_histories.last.updated_at.to_i).to eq new_order.state_updated_at.to_i
      end
    end

    context 'when an order changes state' do
      it 'creates a new state history object with the new state' do
        order.submit!
        expect(order.state_histories.count).to eq 2 # PENDING and SUBMITTED
        expect(order.state_histories.last.state).to eq Order::SUBMITTED
        expect(order.state_histories.last.updated_at.to_i).to eq order.state_updated_at.to_i
      end
    end
  end

  describe '#last_submitted_at' do
    context 'with a submitted order' do
      it 'returns the time at which the order was submitted' do
        order.submit!
        expect(order.last_submitted_at.to_i).to eq order.state_histories.find_by(state: Order::SUBMITTED).updated_at.to_i
      end
    end

    context 'with an unsubmitted order' do
      it 'returns nil' do
        expect(order.last_submitted_at).to be_nil
      end
    end
  end

  describe '#last_approved_at' do
    context 'with an approved order' do
      it 'returns the time at which the order was approved' do
        order.update!(state: Order::SUBMITTED)
        order.approve!
        expect(order.last_approved_at.to_i).to eq order.state_histories.find_by(state: Order::APPROVED).updated_at.to_i
      end
    end

    context 'with an un-approved order' do
      it 'returns nil' do
        expect(order.last_approved_at).to be_nil
      end
    end
  end

  describe 'scope_validate' do
    Order::STATES.reject { |state| state == Order::CANCELED }.each do |state|
      let!("#{state}_order".to_sym) { Fabricate(:order, state: state) }
    end

    let!(:canceled_order) { Fabricate(:order, state: Order::CANCELED, state_reason: 'seller_lapsed') }

    describe 'active' do
      it 'returns only active order' do
        orders = Order.active
        expect(orders.count).to eq 2
        expect(orders).to match_array([approved_order, submitted_order])
      end
    end

    describe 'approved' do
      it 'returns only approved order' do
        orders = Order.approved
        expect(orders.count).to eq 1
        expect(orders.first).to eq approved_order
      end
    end

    describe 'by_last_admin_note' do
      let!(:order1) { Fabricate(:order) }
      let!(:order2) { Fabricate(:order) }
      let!(:order3) { Fabricate(:order) }
      let!(:order1_admin_note_1) { Fabricate(:admin_note, order: order1, note_type: 'case_opened_return', created_at: 10.days.ago) }
      let!(:order1_admin_note_2) { Fabricate(:admin_note, order: order1, note_type: 'case_opened_cancellation', created_at: 9.days.ago) }
      let!(:order1_admin_note_3) { Fabricate(:admin_note, order: order1, note_type: 'mediation_contacted_buyer', created_at: 8.days.ago) }
      let!(:order2_admin_note_1) { Fabricate(:admin_note, order: order2, note_type: 'case_opened_return', created_at: 10.days.ago) }

      it 'returns correct orders for case_opened_return' do
        orders = Order.by_last_admin_note('case_opened_return')
        expect(orders).to eq [order2]
      end

      it 'returns correct orders for case mediation_contacted_buyer' do
        orders = Order.by_last_admin_note('mediation_contacted_buyer')
        expect(orders).to eq [order1]
      end

      it 'returns multiple orders for case mediation_contacted_buyer and case_opened_return' do
        orders = Order.by_last_admin_note(%w[mediation_contacted_buyer case_opened_return])
        expect(orders).to match_array([order1, order2])
      end

      it 'returns the only order for case mediation_contacted_buyer and case_opened_cancellation' do
        orders = Order.by_last_admin_note(%w[mediation_contacted_buyer case_opened_cancellation])
        expect(orders).to eq [order1]
      end
    end
  end

  describe '#shipping_address' do
    context 'with a fulfillment type of SHIP' do
      it 'returns an address object with shipping parameters as attributes' do
        order.update!(fulfillment_type: Order::SHIP, shipping_country: 'US', shipping_region: 'NY', shipping_postal_code: '10013', shipping_city: 'New York', shipping_address_line1: '401 Broadway')
        expected_shipping_address = Address.new(
          country: order.shipping_country,
          postal_code: order.shipping_postal_code,
          region: order.shipping_region,
          city: order.shipping_city,
          address_line1: order.shipping_address_line1,
          address_line2: order.shipping_address_line2
        )
        expect(order.shipping_address).to eq expected_shipping_address
      end
    end

    context 'with a fulfillment type of PICKUP' do
      it 'returns nil' do
        order.update!(fulfillment_type: Order::PICKUP)
        expect(order.shipping_address).to be_nil
      end

      context 'with nil fulfillment type' do
        it 'returns nil' do
          expect(order.shipping_address).to be_nil
        end
      end
    end
  end

  describe 'shipping_info?' do
    context 'SHIP' do
      let(:order_shipping_params) { { fulfillment_type: Order::SHIP, shipping_name: 'Col', shipping_address_line1: 'Address line', shipping_city: 'Brooklyn', shipping_country: 'US', buyer_phone_number: '123' } }
      it 'does not require postal code' do
        order = Fabricate(:order, fulfillment_type: Order::SHIP, shipping_name: 'Col', shipping_address_line1: 'Address line', shipping_city: 'Brooklyn', shipping_country: 'US', buyer_phone_number: '123')
        expect(order.shipping_info?).to be true
      end

      %i[shipping_name shipping_address_line1 shipping_city shipping_country buyer_phone_number].each do |attr|
        it "requires #{attr}" do
          order = Fabricate(:order, order_shipping_params.except(attr))
          expect(order.shipping_info?).to be false
        end
      end
    end

    context 'PICKUP' do
      it 'does not require any shipping field' do
        order = Fabricate(:order, fulfillment_type: Order::PICKUP, shipping_name: nil, shipping_address_line1: nil, shipping_city: nil, shipping_country: nil, buyer_phone_number: nil)
        expect(order.shipping_info?).to be true
      end
    end
  end

  describe '#last_transaction_failed?' do
    context 'with an offer order' do
      let(:order) { Fabricate(:order, mode: Order::OFFER, offers: [Fabricate(:offer)]) }

      it 'returns false if there are no transactions' do
        expect(order.last_transaction_failed?).to be false
      end

      it 'returns false if there are no failed transactions' do
        Fabricate(:transaction, order: order, status: Transaction::SUCCESS)
        expect(order.last_transaction_failed?).to be false
      end

      it 'returns false if the last transaction is a success' do
        Fabricate(:transaction, order: order, status: Transaction::FAILURE)
        Fabricate(:transaction, order: order, status: Transaction::SUCCESS)
        expect(order.last_transaction_failed?).to be false
      end

      it 'returns true if the last transaction is a failure' do
        Fabricate(:transaction, order: order, status: Transaction::SUCCESS)
        Fabricate(:transaction, order: order, status: Transaction::FAILURE)
        expect(order.last_transaction_failed?).to be true
      end
    end
  end

  describe '#competing_orders' do
    context 'with an order that is not submitted' do
      it 'returns an empty array' do
        order = Fabricate(:order, state: Order::PENDING)
        expect(order.competing_orders).to eq []
      end
    end

    context 'with an order that is submitted' do
      context 'with an order that has no competition' do
        it 'returns an empty array' do
          order = Fabricate(:order, state: Order::SUBMITTED)
          expect(order.competing_orders).to eq []
        end
      end

      context 'with an order that has competition' do
        context 'when the competition is not submitted' do
          it 'returns an empty array' do
            order = Fabricate(:order, state: Order::SUBMITTED)
            line_item = Fabricate(:line_item, order: order, artwork_id: 'very-wet-painting')

            competing_order = Fabricate(:order, state: Order::PENDING)
            Fabricate(:line_item, order: competing_order, artwork_id: line_item.artwork_id)
            expect(order.competing_orders).to eq []
          end
        end

        context 'when the competition is submitted' do
          it 'returns those completing orders' do
            order = Fabricate(:order, state: Order::SUBMITTED)
            line_item = Fabricate(:line_item, order: order, artwork_id: 'very-wet-painting')

            competing_order = Fabricate(:order, state: Order::SUBMITTED)
            Fabricate(:line_item, order: competing_order, artwork_id: line_item.artwork_id)
            expect(order.competing_orders).to eq [competing_order]
          end
        end

        context 'with an order that has multiple line items' do
          it 'returns the competition for all line items' do
            order = Fabricate(:order, state: Order::SUBMITTED)
            line_item1 = Fabricate(:line_item, order: order, artwork_id: 'very-wet-painting')
            line_item2 = Fabricate(:line_item, order: order, artwork_id: 'cracked-painting')

            competing_order1 = Fabricate(:order, state: Order::SUBMITTED)
            Fabricate(:line_item, order: competing_order1, artwork_id: line_item1.artwork_id)
            competing_order2 = Fabricate(:order, state: Order::SUBMITTED)
            Fabricate(:line_item, order: competing_order2, artwork_id: line_item2.artwork_id)

            expect(order.competing_orders).to match_array [competing_order1, competing_order2]
          end
        end

        context 'with edition set competition' do
          it 'returns those competing orders' do
            order = Fabricate(:order, state: Order::SUBMITTED)
            line_item1 = Fabricate(:line_item, order: order, edition_set_id: 'very-wet-painting')
            line_item2 = Fabricate(:line_item, order: order, edition_set_id: 'cracked-painting')

            competing_order1 = Fabricate(:order, state: Order::SUBMITTED)
            Fabricate(:line_item, order: competing_order1, edition_set_id: line_item1.edition_set_id)
            competing_order2 = Fabricate(:order, state: Order::SUBMITTED)
            Fabricate(:line_item, order: competing_order2, edition_set_id: line_item2.edition_set_id)

            expect(order.competing_orders).to match_array [competing_order1, competing_order2]
          end
        end
      end
    end
  end
end
