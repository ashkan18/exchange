module Offers
  class AddPendingCounterOfferService
    attr_reader :offer
    include OrderValidator
    def initialize(counter_on, amount_cents:, from_id:, from_type:)
      @counter_on = counter_on
      @order = counter_on.order
      @amount_cents = amount_cents
      @from_id = from_id
      @from_type = from_type
    end

    def process!
      validate_action!

      @offer = @order.offers.create!(
        amount_cents: @amount_cents,
        from_id: @from_id,
        from_type: @from_type,
        creator_id: @from_id,
        responds_to: @counter_on
      )
      totals_service = OfferTotalUpdaterService.new(@offer)
      totals_service.process!
    end

    private

    def validate_action!
      validate_is_last_offer!(@counter_on)
      validate_order_submitted!(@counter_on.order)
    end
  end
end
