class AddSubmittedAtToOffers < ActiveRecord::Migration[5.2]
  def change
    add_column :offers, :submitted_at, :datetime
  end
end
