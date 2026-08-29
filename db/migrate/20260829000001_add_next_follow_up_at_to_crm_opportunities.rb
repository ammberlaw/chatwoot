class AddNextFollowUpAtToCrmOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_opportunities, :next_follow_up_at, :datetime
  end
end
