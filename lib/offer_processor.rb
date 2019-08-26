class OfferProcessor
  attr_accessor :offer, :order, :user_id, :transaction

  def initialize(offer, user_id = nil)
    @offer = offer
    @order = offer.order
    @user_id = user_id
    @state_changed = false
  end

  def validate_offer!
    raise Errors::ValidationError, :invalid_offer if offer.submitted?
  end

  def check_inventory!
    raise Errors::InsufficientInventoryError unless order.inventory?
  end

  def validate_order!
    raise Errors::ValidationError, :cant_submit unless order.mode == Order::OFFER
    raise Errors::ValidationError, :missing_required_info unless order.can_commit?

    unless order.valid_artwork_version?
      Exchange.dogstatsd.increment 'submit.artwork_version_mismatch'
      raise Errors::ProcessingError, :artwork_version_mismatch
    end
    credit_card_error = order.assert_credit_card
    raise Errors::ValidationError, credit_card_error if credit_card_error
  end

  def submit_order!
    order.submit!
    @state_changed = true
  end

  def confirm_payment_method!
    existing_confirmation_attempt = order.transactions.where(external_type: Transaction::SETUP_INTENT).order(created_at: :desc)&.first
    if existing_confirmation_attempt && existing_confirmation_attempt.source_id == order.credit_card[:external_id]
      # we have an ongoing setup intent with this card, check if it's confirmed
      PaymentMethodService.verify(existing_confirmation_attempt)
    else
      @transaction = PaymentMethodService.confirm_payment_method!(offer.order)
      order.transactions << transaction
      return unless @transaction.requires_action?

      Exchange.dogstatsd.increment 'offer.requires_action'
      raise Errors::PaymentRequiresActionError, transaction.action_data
    end
  end

  def set_order_totals!
    offer_order_totals = OfferOrderTotals.new(offer)
    order.update!(
      last_offer: offer,
      shipping_total_cents: offer_order_totals.shipping_total_cents,
      tax_total_cents: offer_order_totals.tax_total_cents,
      commission_rate: offer_order_totals.commission_rate,
      items_total_cents: offer_order_totals.items_total_cents,
      buyer_total_cents: offer_order_totals.buyer_total_cents,
      commission_fee_cents: offer_order_totals.commission_fee_cents,
      transaction_fee_cents: offer_order_totals.transaction_fee_cents,
      seller_total_cents: offer_order_totals.seller_total_cents,
      state_expires_at: Offer::EXPIRATION.from_now # expand order expiration
    )
  end

  def update_offer_submission_timestamp
    offer.update!(submitted_at: Time.now.utc)
  end

  def on_success
    OrderFollowUpJob.set(wait_until: offer.order.state_expires_at).perform_later(offer.order.id, offer.order.state)
    OfferEvent.delay_post(offer, OfferEvent::SUBMITTED)
    OfferRespondReminderJob.set(wait_until: offer.order.state_expires_at - Order::DEFAULT_EXPIRATION_REMINDER)
                           .perform_later(offer.order.id, offer.id)
    Exchange.dogstatsd.increment 'offer.submit'
  end

  def order_on_success
    OrderEvent.delay_post(order, Order::SUBMITTED, user_id)
    Exchange.dogstatsd.increment 'order.submit'
  end
end
