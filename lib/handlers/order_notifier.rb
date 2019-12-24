class Handlers::OrderNotifier
  def call(event)
    case event
    when Commands::OrderCreated
      order = Order.find(event.data[:id])
      Exchange.dogstatsd.increment 'order.create'
      OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(order.id, order.state)
    end
  end
end
