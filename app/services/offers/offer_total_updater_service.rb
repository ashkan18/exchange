module Offers
  class OfferTotalUpdaterService < BaseTotalCalculatorService
    def initialize(offer)
      @pending_offer = offer
      @order = offer.order
    end

    def process!
      set_offer_totals!
    end

    attr_reader :offer
  end
end
