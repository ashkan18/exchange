module OrderService
  def self.create_with_artwork!(buyer_id:, buyer_type:, mode:, quantity:, artwork_id:, edition_set_id: nil, user_agent:, user_ip:, find_active_or_create: false)
    order_creator = OrderCreator.new(
      buyer_id: buyer_id,
      buyer_type: buyer_type,
      mode: mode,
      quantity: quantity,
      artwork_id: artwork_id,
      edition_set_id: edition_set_id,
      user_agent: user_agent,
      user_ip: user_ip
    )

    # in case of Offer orders, we want to reuse existing pending/submitted offers
    create_method = find_active_or_create ? :find_or_create! : :create!
    order_creator.send(create_method) do |created_order|
      Exchange.dogstatsd.increment 'order.create'
      OrderFollowUpJob.set(wait_until: created_order.state_expires_at).perform_later(created_order.id, created_order.state)
    end
  end

  def self.set_shipping!(order, fulfillment_type:, shipping:)
    raise Errors::ValidationError, :invalid_state unless order.state == Order::PENDING

    order_shipping = OrderShipping.new(order)
    case fulfillment_type
    when Order::PICKUP then order_shipping.pickup!
    when Order::SHIP then order_shipping.ship!(shipping)
    end
    order
  end

  def self.set_payment!(order, credit_card_id)
    credit_card = Gravity.get_credit_card(credit_card_id)
    raise Errors::ValidationError.new(:invalid_credit_card, credit_card_id: credit_card_id) unless credit_card.dig(:user, :_id) == order.buyer_id

    order.update!(credit_card_id: credit_card_id)
    order
  end

  def self.submit!(order, user_id)
    unless order.valid_artwork_version?
      Exchange.dogstatsd.increment 'submit.artwork_version_mismatch'
      raise Errors::ProcessingError, :artwork_version_mismatch
    end

    order_processor = OrderProcessor.new(order, user_id)
    raise Errors::ValidationError, order_processor.validation_error unless order_processor.valid?

    order.submit! do
      order.line_items.each { |li| li.update!(commission_fee_cents: li.current_commission_fee_cents) }
      totals = BuyOrderTotals.new(order)
      order.update!(
        transaction_fee_cents: totals.transaction_fee_cents,
        commission_rate: order.current_commission_rate,
        commission_fee_cents: totals.commission_fee_cents,
        seller_total_cents: totals.seller_total_cents
      )
      order_processor.hold!
      raise Errors::InsufficientInventoryError if order_processor.failed_inventory?
      # in case of failed transaction, we need to rollback this block,
      # but still need to add transaction, so we raise an ActiveRecord::Rollback
      raise ActiveRecord::Rollback if order_processor.failed_payment? || order_processor.requires_action?

      order.update!(external_charge_id: order_processor.transaction.external_id)
    end

    order.transactions << order_processor.transaction
    PostTransactionNotificationJob.perform_later(order_processor.transaction.id, user_id)
    raise Errors::FailedTransactionError.new(:charge_authorization_failed, order_processor.transaction) if order_processor.failed_payment?

    if order_processor.requires_action?
      # because of an issue with `ActiveRecord::Rollback` we have to force a reload here
      # rollback does not clean the model and calling update on it will raise error
      order.reload.update!(external_charge_id: order_processor.transaction.external_id)
      raise Errors::PaymentRequiresActionError, order_processor.action_data
    end

    OrderEvent.delay_post(order, Order::SUBMITTED, user_id)
    OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(order.id, order.state)
    ReminderFollowUpJob.set(wait_until: order.state_expiration_reminder_time).perform_later(order.id, order.state)
    Exchange.dogstatsd.increment 'order.submitted'
    order
  end

  def self.fulfill_at_once!(order, fulfillment, user_id)
    order.fulfill! do
      fulfillment = Fulfillment.create!(fulfillment.slice(:courier, :tracking_id, :estimated_delivery))
      order.line_items.each do |li|
        li.line_item_fulfillments.create!(fulfillment_id: fulfillment.id)
      end
    end
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.confirm_pickup!(order, user_id)
    raise Errors::ValidationError, :wrong_fulfillment_type unless order.fulfillment_type == Order::PICKUP

    order.fulfill!
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.confirm_fulfillment!(order, user_id)
    raise Errors::ValidationError, :wrong_fulfillment_type unless order.fulfillment_type == Order::SHIP

    order.fulfill!
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.abandon!(order)
    order.abandon!
  end
end
