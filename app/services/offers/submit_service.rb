class Offers::SubmitService
  OFFER_EXPIRATION = 2.days

  def initialize(offer, by)
    @offer = offer
    @by = by
  end

  def process!
    assert_submit!
    case @offer.order.state
    when Order::PENDING then submit_order
    when Order::SUBMITTED then submit_offer
    end
  end

  private

  def assert_submit!
    raise Errors::ValidationError, :already_submitted if @offer.submitted_at.present?
    raise Errors::ValidationError, :invalid_state unless [Order::PENDING, Order::SUBMITTED].include? @offer.order.state
  end

  def submit_order
    @offer.order.submit! do
      @offer.update!(submitted_at: Time.now.utc)
    end
    Exchange.dogstatsd.increment 'offer.submit'
    PostNotificationJob.perform_later(@offer.order.id, Order::SUBMITTED, @by)
    OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(@order.id, @order.state)
    ReminderFollowUpJob.set(wait_until: @order.state_expires_at - 2.hours).perform_later(@order.id, @order.state)
  end

  def submit_offer
    @offer.with_lock do
      @offer.update!(submitted_at: Time.now.utc)
      @offer.order.update!(last_offer: @offer, state_expires_at: OFFER_EXPIRATION.from_now)
    end
    Exchange.dogstatsd.increment 'offer.submit'
    PostNotificationJob.perform_later(@offer.order.id, Order::SUBMITTED, @by)
    OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(@order.id, @order.state)
    ReminderFollowUpJob.set(wait_until: @order.state_expires_at - 2.hours).perform_later(@order.id, @order.state)
  end
end
