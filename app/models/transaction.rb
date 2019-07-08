class Transaction < ApplicationRecord
  has_paper_trail versions: { class_name: 'PaperTrail::TransactionVersion' }

  belongs_to :order

  TYPES = [
    HOLD = 'hold'.freeze,
    CAPTURE = 'capture'.freeze,
    REFUND = 'refund'.freeze
  ].freeze

  STATUSES = [
    SUCCESS = 'success'.freeze,
    FAILURE = 'failure'.freeze
  ].freeze

  def to_s
    failed? ? "#{id}: #{failure_code} - #{failure_message}" : id
  end

  def failed?
    status == FAILURE
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
