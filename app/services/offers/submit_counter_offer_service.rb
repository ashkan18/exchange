module Offers
  class SubmitCounterOfferService
    include OfferValidationService
    def initialize(pending_offer:, from_id:)
      @offer = pending_offer
      @order = offer.order
      @from_id = from_id
    end

    def process!
      validate_offer_is_mine!(offer, @from_id)
      validate_offer_order_is_submitted!(offer)
      validate_offer_not_submitted!(offer)

      @offer.update!(submitted_at: Time.now.utc)
      @order.update!(last_offer: @offer)

      totals_service = OfferTotalUpdaterService.new(offer: @offer)
      totals_service.process!

      instrument_offer_counter
    end

    private

    attr_reader :offer

    def instrument_offer_counter
      Exchange.dogstatsd.increment 'offer.counter'
    end
  end
end
