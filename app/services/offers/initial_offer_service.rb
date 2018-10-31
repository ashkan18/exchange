module Offers
  class InitialOfferService
    attr_reader :order, :offer
    def initialize(order, amount_cents, user_id)
      @order = order
      @amount_cents = amount_cents
      @user_id = user_id
      @offer = nil
    end

    def process!
      assert_offer!
      @order.with_lock do
        @offer = @order.offers.create!(amount_cents: @amount_cents, from_id: @user_id, from_type: Order::USER, creator_id: @user_id)
        @order.update!(last_offer: @offer)
        OrderTotalUpdaterService.new(@order).update_totals!
      end
    end

    private

    def assert_offer!
      raise Errors::ValidationError, :cant_offer unless @order.mode == Order::OFFER && @order.state == Order::PENDING
      raise Errors::ValidationError, :invalid_amount_cents unless @amount_cents.present? && @amount_cents.positive?
    end
  end
end
