class AddIsAuctionToOrders < ActiveRecord::Migration[5.2]
  def change
    add_column :orders, :auction, :boolean, default: false
  end
end
