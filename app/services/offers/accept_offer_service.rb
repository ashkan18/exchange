module Offers
  class AcceptOfferService < CommitOrderService
    include OrderValidator
    attr_reader :order, :offer, :user_id
    def initialize(offer:, order:, user_id: nil)
      super(order, :approve, user_id)
      @offer = offer
    end

    private

    def process_payment
      @transaction = PaymentService.create_and_capture_charge(construct_charge_params)
      raise Errors::ProcessingError.new(:capture_failed, @transaction.failure_data) if @transaction.failed?
    end

    def pre_process!
      super
      validate_is_last_offer!(@offer)
    end

    def post_process!
      super
      PostOrderNotificationJob.perform_later(@order.id, Order::APPROVED, @user_id)
    end
  end
end
