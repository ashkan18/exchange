class Types::OrderType < Types::BaseObject
  description 'An Order'
  graphql_name 'Order'

  field :id, ID, null: false
  field :mode, Types::OrderModeEnum, null: true
  field :code, String, null: false
  field :buyer_phone_number, String, null: true
  field :buyer_total_cents, Integer, null: true
  field :buyer, Types::OrderPartyUnionType, null: false
  field :commission_fee_cents, Integer, null: true, seller_only: true
  field :commission_rate, Float, null: true
  field :created_at, Types::DateTimeType, null: false
  field :credit_card_id, String, null: true
  field :currency_code, String, null: false
  field :display_commission_rate, String, null: true
  field :items_total_cents, Integer, null: false
  field :last_approved_at, Types::DateTimeType, null: true
  field :last_submitted_at, Types::DateTimeType, null: true
  field :line_items, Types::LineItemType.connection_type, null: true
  field :requested_fulfillment, Types::RequestedFulfillmentUnionType, null: true
  field :seller_total_cents, Integer, null: true, seller_only: true
  field :seller, Types::OrderPartyUnionType, null: false
  field :shipping_total_cents, Integer, null: true
  field :state_expires_at, Types::DateTimeType, null: true
  field :state_reason, String, null: true
  field :state_updated_at, Types::DateTimeType, null: true
  field :state, Types::OrderStateEnum, null: false
  field :offers, Types::OfferType.connection_type, null: true do
    argument :from_id, String, required: false
    argument :from_type, String, required: false
  end
  field :last_offer, Types::OfferType, null: true
  field :tax_total_cents, Integer, null: true
  field :transaction_fee_cents, Integer, null: true, seller_only: true
  field :updated_at, Types::DateTimeType, null: false

  def buyer
    OpenStruct.new(
      id: object.buyer_id,
      type: object.buyer_type
    )
  end

  def seller
    OpenStruct.new(
      id: object.seller_id,
      type: object.seller_type
    )
  end

  def requested_fulfillment
    # fulfillment is not a field on order so we have to resolve it here
    # it uses our union, for that to work we need to pass order (aka object)
    # to our Fulfillment
    return if object.fulfillment_type.blank?

    object
  end

  def display_commission_rate
    return if object.commission_rate.nil?

    ActiveSupport::NumberHelper.number_to_percentage(
      object.commission_rate * 100,
      precision: 2,
      strip_insignificant_zeros: true
    )
  end

  def offers(**args)
    if args.keys.any? { |ar| %i[from_id from_type].include? ar }
      object.offers.where(args.slice(:from_id, :from_type, :state))
    else
      object.offers.all
    end
  end
end
