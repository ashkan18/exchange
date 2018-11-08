class AddStateToOffers < ActiveRecord::Migration[5.2]
  def change
    add_column :offers, :state, :string, null: false
  end
end
