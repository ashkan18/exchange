class Transaction < ApplicationRecord
  has_paper_trail versions: { class_name: 'PaperTrail::TransactionVersion' }

  belongs_to :order

  EXTERNAL_TYPES = [
    PAYMENT_INTENT = 'payment_intent'.freeze,
    CHARGE = 'charge'.freeze
  ].freeze

  TYPES = [
    HOLD = 'hold'.freeze,
    CAPTURE = 'capture'.freeze,
    REFUND = 'refund'.freeze,
    CONFIRM = 'confirm'.freeze
  ].freeze

  STATUSES = [
    SUCCESS = 'success'.freeze,
    FAILURE = 'failure'.freeze,
    REQUIRES_ACTION = 'requires_action'.freeze,
    REQUIRES_CAPTURE = 'requires_capture'.freeze
  ].freeze

  def to_s
    failed? ? "#{id}: #{failure_code} - #{failure_message}" : id
  end

  def failed?
    status == FAILURE
  end

  def requires_action?
    status == REQUIRES_ACTION
  end

  def failure_data
    {
      id: id,
      failure_code: failure_code,
      failure_message: failure_message,
      decline_code: decline_code
    }
  end
end
