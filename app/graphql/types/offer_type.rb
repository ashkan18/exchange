class Types::OfferType < Types::BaseObject
  description 'An Offer'
  graphql_name 'Offer'

  field :id, ID, null: false
  field :from, Types::OrderPartyUnionType, null: false
  field :amount_cents, Integer, null: false
  field :creator_id, String, null: false
  field :created_at, Types::DateTimeType, null: false
  field :submitted_at, Types::DateTimeType, null: true
  field :order, Types::OrderType, null: false
  field :responds_to, Types::OfferType, null: true

  def from
    OpenStruct.new(
      id: object.from_id,
      type: object.from_type
    )
  end
end
