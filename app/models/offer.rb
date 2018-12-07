class Offer < ApplicationRecord
  belongs_to :order
  belongs_to :responds_to, class_name: 'Offer', optional: true

  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :pending, -> { where(submitted_at: nil) }

  def last_offer?
    order.last_offer == self
  end

  def submitted?
    submitted_at.present?
  end

  def from_participant
    if from_id == order.seller_id && from_type == order.seller_type
      Order::SELLER
    elsif from_id == order.buyer_id && from_type == order.buyer_type
      Order::BUYER
    end
  end

  def awaiting_for_response_from
    return if submitted?
    case from_participant
    when Order::BUYER then Order::SELLER
    when Order::SELLER then Order::BUYER
    end
  end
end
