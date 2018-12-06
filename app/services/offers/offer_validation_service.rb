module Offers
  module OfferValidationService
    def validate_is_last_offer!(offer)
      raise Errors::ValidationError, :not_last_offer unless offer.last_offer?
    end

    def validate_offer_is_from_buyer!(offer)
      raise Errors::ValidationError, :offer_not_from_buyer unless offer.from_type == Order::USER
    end

    def validate_order_submitted!(order)
      raise Errors::ValidationError, :invalid_state unless order.state == Order::SUBMITTED
    end

    def validate_owner!(offer, from_id)
      raise Errors::ValidationError, :not_offerable unless offer.from_id == from_id
    end
  end
end
