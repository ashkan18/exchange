class OrderProcessor
  ##
  # Responsible for processing an order which means deduct the inventory of work and process the charge
  #
  # provides methods for `hold!` and `charge!`. Both of these try to first deduct the inventory and then try to process payment.
  # Caller should check `failed_inventory?` and `failed_payment?` errors to verify the success of hold/charge.
  # In case of `failed_payment?`, the actual payment error can be accessed via the `transaction` attribute of the processor.
  #
  # the caller needs to verify the results by checking `failed_inventory?` and `failed_payment?` methods.

  attr_accessor :order, :transaction, :validation_error

  def initialize(order, user_id)
    @order = order
    @user_id = user_id
    @validation_error = nil
    @transaction = nil
    @deducted_inventory = []
    @validated = false
    @insufficient_inventory = false
    @totals_set = false
  end

  def undo!(state_transition = nil)
    undeduct_inventory! unless @deducted_inventory.empty?
    reset_totals! if @totals_set
    transition(state_transition) if state_transition.present?
  end

  def reset_totals!
    order.line_items.each { |li|  li.update!(commission_fee_cents: nil) }
    order.update!(transaction_fee_cents: nil, commission_rate: nil, commission_fee_cents: nil, seller_total_cents: nil)
  end


  def transition(action)
    order.send(action)
  end

  def set_totals!
    order.line_items.each { |li| li.update!(commission_fee_cents: li.current_commission_fee_cents) }
    totals = BuyOrderTotals.new(order)
    order.update!(
      transaction_fee_cents: totals.transaction_fee_cents,
      commission_rate: order.current_commission_rate,
      commission_fee_cents: totals.commission_fee_cents,
      seller_total_cents: totals.seller_total_cents
    )
    @totals_set = true
  end

  def hold!
    raise Errors::ValidationError, @validation_error unless valid?

    @transaction = if @order.external_charge_id
      # we already have a payment intent on this order
      PaymentService.confirm_payment_intent(@order.external_charge_id)
    else
      PaymentService.hold_payment(construct_charge_params)
    end
  end

  def charge!
    raise Errors::ValidationError, @validation_error unless valid?

    @transaction = PaymentService.capture_without_hold(construct_charge_params)
  rescue Errors::InsufficientInventoryError
    undeduct_inventory
    @insufficient_inventory = true
  end

  def failed_payment?
    @transaction&.failed?
  end

  def requires_action?
    @transaction&.requires_action?
  end

  def action_data
    requires_action? && { client_secret: @transaction.payload['client_secret'] }
  end

  def failed_inventory?
    @insufficient_inventory
  end

  def valid?
    @validated ||= begin
      @validation_error = :unsupported_payment_method unless @order.payment_method == Order::CREDIT_CARD
      @validation_error ||= :missing_required_info unless @order.can_commit?
      @validation_error ||= @order.assert_credit_card
    end
    @validation_error.nil?
  end

  def undeduct_inventory!
    @deducted_inventory.each { |li| Gravity.undeduct_inventory(li) }
    @deducted_inventory = []
  end

  def deduct_inventory!
    # Try holding artwork and deduct inventory
    @order.line_items.each do |li|
      Gravity.deduct_inventory(li)
      @deducted_inventory << li
    end
  rescue Errors::InsufficientInventoryError
    undeduct_inventory
    @insufficient_inventory = true
  end

  def store_transaction
    order.transactions << transaction
    PostTransactionNotificationJob.perform_later(transaction.id, @user_id)
  end

  def set_payment!
    @order.update!(external_charge_id: transaction.external_id)
  end

  def set_follow_ups
    OrderEvent.delay_post(order, Order::SUBMITTED, @user_id)
    OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(order.id, order.state)
    ReminderFollowUpJob.set(wait_until: order.state_expiration_reminder_time).perform_later(order.id, order.state)
    Exchange.dogstatsd.increment 'order.submitted'
  end

  def construct_charge_params
    {
      credit_card: @order.credit_card,
      buyer_amount: @order.buyer_total_cents,
      merchant_account: @order.merchant_account,
      seller_amount: @order.seller_total_cents,
      currency_code: @order.currency_code,
      metadata: charge_metadata,
      description: charge_description
    }
  end

  def charge_description
    partner_name = (@order.partner[:name] || '').parameterize[0...12].upcase
    "#{partner_name} via Artsy"
  end

  def charge_metadata
    {
      exchange_order_id: @order.id,
      buyer_id: @order.buyer_id,
      buyer_type: @order.buyer_type,
      seller_id: @order.seller_id,
      seller_type: @order.seller_type,
      type: @order.auction_seller? ? 'auction-bn' : 'bn-mo'
    }
  end
end
