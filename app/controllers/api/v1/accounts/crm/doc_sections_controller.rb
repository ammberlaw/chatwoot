# 文档中心资料板块：index 返回当前用户可见的板块（管理员/文档中心负责人全量），
# update 仅管理员（配置各板块可见部门）。
class Api::V1::Accounts::Crm::DocSectionsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def index
    Crm::DocSection.ensure_defaults!(Current.account)
    all = Current.account.crm_doc_sections.order(:position, :id)
    @sections = if manage_all?
                  all
                else
                  all.where(id: Crm::DocSection.visible_ids_for(Current.account, current_user.id))
                end
  end

  def update
    @section = Current.account.crm_doc_sections.find(params[:id])
    @section.update!(department_ids: Array(params.dig(:section, :department_ids)).map(&:to_i).uniq)
    render json: { id: @section.id, name: @section.name, department_ids: @section.department_ids }
  end

  private

  def manage_all?
    Current.account_user.administrator? ||
      Crm::DocCenterSetting.for_account(Current.account).owner_id == current_user.id
  end

  def check_authorization
    authorize(Crm::DocSection)
  end
end
