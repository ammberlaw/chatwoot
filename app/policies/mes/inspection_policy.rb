class Mes::InspectionPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:quality)

  # 质检报告暂存 blob：与建单同权。
  def stage_blob? = create?

  # 改 / 删：质检岗即可，具体是不是本人由控制器的 ensure_owner_or_admin!(:inspector_id) 判
  # ——和生产报工「谁报工谁删」同一套口径。
  #
  # 原来写死 administrator?，在本人判断之前就把人挡了：车间自己录错一条，
  # 得去求管理员删（2026-10-29 反馈）。
  #
  # 为什么是删不是作废：质检记录不动库存、不推阶段、不出凭证，作废要冲销的东西它一样没有。
  # 风险在看板合格率＝(检验量−不良量)/检验量 按记录加总算，删掉一条不良会让它悄悄变好看，
  # 所以用本人限制挡住「抹别人的不良记录」。
  def update? = @account_user.mes_can?(:quality)
  def destroy? = @account_user.mes_can?(:quality)
end

Mes::InspectionPolicy.prepend_mod_with('Mes::InspectionPolicy')
