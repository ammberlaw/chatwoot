class CreateChannelWhatsappWeb < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_whatsapp_web do |t|
      t.integer :account_id, null: false
      # Nullable until the agent completes the QR scan and the bridge reports the linked number.
      t.string :phone_number
      t.jsonb :provider_config, default: {}, null: false

      t.timestamps
    end

    add_index :channel_whatsapp_web, :phone_number, unique: true, where: 'phone_number IS NOT NULL'
    add_index :channel_whatsapp_web, :account_id
  end
end
