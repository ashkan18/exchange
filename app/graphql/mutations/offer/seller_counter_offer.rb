class Mutations::Offer::SellerCounterOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :amount_cents, Integer, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:, amount_cents:)
    offer = Offer.find(offer_id)
    validate_request!(offer)

    add_service = Offers::AddPendingCounterOfferService.new(offer, amount_cents: amount_cents, from_type: Order::PARTNER, from_id: context[:current_user][:id])
    add_service.process!

    submit_service = Offers::SubmitCounterOfferService.new(add_service.offer, user_id: context[:current_user][:id])
    submit_service.process!

    { order_or_error: { order: submit_service.offer.order } }
  rescue Errors::ApplicationError => e
    { order_or_error: { error: Types::ApplicationErrorType.from_application(e) } }
  end

  private

  def validate_request!(offer)
    authorize_seller_request!(offer)
    raise Errors::ValidationError, :cannot_counter unless offer.awaiting_response_from == Order::SELLER
  end
end
