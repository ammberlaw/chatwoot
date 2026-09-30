# 视图层取 MES 带岗位人名的入口（逻辑在 Mes::StaffNames，模型层共用同一套）。
# 一次渲染内只建一个实例，岗位表整批读一次。
module MesStaffHelper
  def mes_staff_name(user, hints = nil)
    mes_staff_names.for_user(user, hints)
  end

  def mes_staff_label(user_id, name, hints = nil)
    mes_staff_names.label(user_id, name, hints)
  end

  def mes_staff_names_for(ids, hints = nil)
    mes_staff_names.for_ids(ids, hints)
  end

  private

  def mes_staff_names
    @mes_staff_names ||= Mes::StaffNames.new(Current.account)
  end
end
