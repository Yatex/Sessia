class ChangeUserTimeZoneDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :time_zone, from: "America/Montevideo", to: "UTC"
  end
end
