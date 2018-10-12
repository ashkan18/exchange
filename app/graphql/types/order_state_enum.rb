class Types::OrderStateEnum < Types::BaseEnum
  value 'ABANDONED', 'order is abandoned by buyer and never submitted', value: Order::ABANDONED
  value 'PENDING', 'order is still pending submission by buyer', value: Order::PENDING
  value 'SUBMITTED', 'order is submitted by buyer', value: Order::SUBMITTED
  value 'APPROVED', 'order is approved by seller', value: Order::APPROVED
  value 'CANCELED', 'order is canceled', value: Order::CANCELED
  value 'FULFILLED', 'order is fulfilled by seller', value: Order::FULFILLED
  value 'RETURNED', 'order is refunded and returned after being approved or fulfilled', value: Order::RETURNED
end
