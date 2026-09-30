# MES 人名带岗位：「工程-朱桂权」「采购-何双双」。
# 光一个人名看不出该找哪个岗位的人催单，跨部门时尤其明显。
#
# 没配 MES 岗位的人（业务员、审批用的部门主管/总经理）原样只显示姓名，
# 所以调用方一律套上即可，不必逐处判断这个字段是不是 MES 人员。
#
# 看板、单据详情、转发目标都走这里，保证三处口径一致。
class Mes::StaffNames
  # 场合提示：给身兼多岗的人挑岗位（生产上熊莉莉是 PMC+采购，
  # BOM 单据上要显示 PMC、采购单上要显示采购）。
  ENGINEERING = %w[engineer pmc].freeze
  PURCHASING = %w[buyer].freeze
  WAREHOUSE = %w[warehouse].freeze
  PRODUCTION = %w[production].freeze

  def initialize(account)
    @account = account
  end

  # 一组用户 id → 带岗位的姓名数组，保持传入顺序（查不到的跳过）。
  def for_ids(ids, hints = nil)
    ids = Array(ids)
    return [] if ids.empty?

    found = @account.users.where(id: ids).pluck(:id, :name).to_h
    ids.filter_map { |id| label(id, found[id], hints) }
  end

  def for_user(user, hints = nil)
    user.blank? ? nil : label(user.id, user.name, hints)
  end

  def label(user_id, name, hints = nil)
    return nil if name.blank?

    role = members[user_id]&.mes_role_label(hints)
    role ? "#{role}-#{name}" : name
  end

  private

  # 一个账套配了 MES 岗位的就十来个人，整批读一次缓存住，
  # 免得每个名字都去查一遍 account_users。
  def members
    @members ||= @account.account_users
                         .where('mes_role IS NOT NULL OR COALESCE(array_length(mes_roles, 1), 0) > 0')
                         .index_by(&:user_id)
  end
end
