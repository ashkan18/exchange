module OrderValidator
  def validate_is_last_offer!(offer)
    raise Errors::ValidationError, :not_last_offer unless offer.last_offer?
  end

  def validate_order_submitted!(order)
    raise Errors::ValidationError, :invalid_state unless order.state == Order::SUBMITTED
  end

  def validate_owner!(offer, from_id)
    raise Errors::ValidationError, :not_offerable unless offer.from_id == from_id
  end
end
