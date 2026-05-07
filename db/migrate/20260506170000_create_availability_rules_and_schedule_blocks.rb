class CreateAvailabilityRulesAndScheduleBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :availability_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :weekday, null: false
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :availability_rules, [:user_id, :weekday]
    add_index :availability_rules, [:user_id, :weekday, :start_minute]

    create_table :schedule_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, default: "Blocked time", null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :notes
      t.string :status, default: "active", null: false

      t.timestamps
    end

    add_index :schedule_blocks, [:user_id, :starts_at]
    add_index :schedule_blocks, [:user_id, :status]
  end
end
