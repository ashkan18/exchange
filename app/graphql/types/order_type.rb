class Types::OrderType < Types::BaseObject
  description 'An Order'
  graphql_name 'Order'

  field :id, ID, null: false
  field :code, String, null: false
  field :buyer, Types::OrderPartyUnionType, null: false
  field :seller, Types::OrderPartyUnionType, null: false
  field :credit_card_id, String, null: true
  field :state, Types::OrderStateEnum, null: false
  field :state_reason, String, null: true
  field :currency_code, String, null: false
  field :requested_fulfillment, Types::RequestedFulfillmentUnionType, null: true
  field :items_total_cents, Integer, null: false
  field :shipping_total_cents, Integer, null: true
  field :tax_total_cents, Integer, null: true
  field :transaction_fee_cents, Integer, null: true, seller_only: true
  field :commission_fee_cents, Integer, null: true, seller_only: true
  field :seller_total_cents, Integer, null: true, seller_only: true
  field :buyer_total_cents, Integer, null: true
  field :buyer_phone_number, String, null: true
  field :created_at, Types::DateTimeType, null: false
  field :updated_at, Types::DateTimeType, null: false
  field :state_updated_at, Types::DateTimeType, null: true
  field :state_expires_at, Types::DateTimeType, null: true
  field :last_submitted_at, Types::DateTimeType, null: true
  field :last_approved_at, Types::DateTimeType, null: true
  field :line_items, Types::LineItemType.connection_type, null: true
  field :auction, Boolean, null: false

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
end
