# Only reverse roles granted by organization changes; manual grants remain intact.
class Org::ManagedRoleSync
  def self.perform(account)
    business_leaders = account.org_departments.active.where.not(leader_id: nil).select(&:business_line?).map(&:leader_id).uniq
    account.account_users.where('org_managed_crm_role = TRUE OR user_id IN (?)', business_leaders.presence || [0]).find_each do |member|
      next if member.administrator?

      if member.deactivated_at.nil? && business_leaders.include?(member.user_id)
        if [nil, 'sales'].include?(member.crm_role)
          member.update!(org_previous_crm_role: member.crm_role, crm_role: 'manager', org_managed_crm_role: true)
        end
      elsif member.org_managed_crm_role?
        role = member.crm_role == 'manager' ? member.org_previous_crm_role : member.crm_role
        member.update!(crm_role: role, org_managed_crm_role: false, org_previous_crm_role: nil)
      end
    end
  end
end
