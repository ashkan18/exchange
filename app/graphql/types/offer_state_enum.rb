class Types::OfferStateEnum < Types::BaseEnum
  value 'PENDING', 'offer is still pending submission by buyer', value: Offer::PENDING
  value 'SUBMITTED', 'order is submitted by buyer', value: Order::SUBMITTED
end
