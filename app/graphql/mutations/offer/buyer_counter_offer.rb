class Mutations::Offer::BuyerCounterOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :amount_cents, Integer, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:, amount_cents:)
    offer = Offer.find(offer_id)

    validate_request(offer)

    add_service = Offers::AddPendingCounterOfferService.new(offer, amount_cents: amount_cents, from_type: Order::USER, from_id: context[:current_user][:id])
    add_service.process!

    { order_or_error: { order: add_service.offer.order } }
  rescue Errors::ApplicationError => e
    { order_or_error: { error: Types::ApplicationErrorType.from_application(e) } }
  end

  private

  def validate_request(offer)
    authorize_buyer_request!(offer)
    offer.awaiting_response_from == Order::BUYER
  end
end
