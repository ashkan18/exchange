module Offers
  module OfferValidationService
    def validate_is_last_offer!(offer)
      raise Errors::ValidationError.new(:not_last_offer, offer) unless offer.last_offer?
    end

    def validate_offer_is_from_buyer!(offer)
      raise Errors::ValidationError.new(:offer_not_from_buyer, offer) unless offer.from_type == Order::USER
    end

    def validate_offer_order_is_submitted!(offer)
      raise Errors::ValidationError.new(:invalid_state, offer) unless offer.order.state == Order::SUBMITTED
    end

    def validate_offer_not_submitted!(offer)
      raise Errors::ValidationError.new(:invalid_state, offer) unless offer.submitted_at.nil?
    end

    def validate_offer_is_mine!(offer, from_id)
      raise Errors::ValidationError.new(:not_offerable, offer) unless offer.from_id == from_id
    end
  end
end
