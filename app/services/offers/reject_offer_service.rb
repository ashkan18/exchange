module Offers
  class RejectOfferService
    include OrderValidator
    def initialize(offer:, reject_reason:)
      @offer = offer
      @reject_reason = reject_reason
    end

    def process!
      pre_process!

      @offer.order.reject!(@reject_reason)

      post_process!
    end

    private

    def pre_process!
      validate_is_last_offer!(@offer)
    end

    def post_process!
      Exchange.dogstatsd.increment 'offer.reject'
    end
  end
end
