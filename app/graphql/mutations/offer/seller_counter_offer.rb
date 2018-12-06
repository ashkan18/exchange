class Mutations::Offer::SellerCounterOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :amount_cents, Integer, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:, amount_cents:)
    offer = Offer.find(offer_id)
    authorize_seller_request!(offer)
    raise Errors::ValidationError, :cannot_counter unless waiting_seller_counter?(offer)

    add_service = Offers::AddPendingCounterOfferService.new(counter_on: offer, amount_cents: amount_cents, from_type: Order::PARTNER, from_id: context[:current_user][:id])
    add_service.process!

    submit_service = Offers::SubmitCounterOfferService.new(add_service.offer, user_id: context[:current_user][:id])
    submit_service.process!

    { order_or_error: { order: submit_service.offer.order } }
  rescue Errors::ApplicationError => e
    { order_or_error: { error: Types::ApplicationErrorType.from_application(e) } }
  end

  private

  def waiting_seller_counter?(offer)
    offer.from_participant == Order::BUYER
  end
end
