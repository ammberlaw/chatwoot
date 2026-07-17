# 文档中心资料板块：index 返回当前用户可见的板块（管理员/文档中心负责人全量），
# create/update/destroy 仅管理员（自定义板块 + 配置各板块可见部门）。
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

  # 管理员自定义新增板块（排在默认板块之后）。
  def create
    name = params.dig(:section, :name).to_s.strip
    return render json: { error: '板块名称不能为空' }, status: :unprocessable_entity if name.blank?

    position = (Current.account.crm_doc_sections.maximum(:position) || 0) + 1
    @section = Current.account.crm_doc_sections.create!(name: name, position: position)
    render json: section_json(@section)
  end

  def update
    @section = Current.account.crm_doc_sections.find(params[:id])
    @section.update!(department_ids: Array(params.dig(:section, :department_ids)).map(&:to_i).uniq)
    render json: section_json(@section)
  end

  # 默认板块随 index 自动重建，只允许删自定义板块；板块下文档回落为「未分板块」。
  def destroy
    section = Current.account.crm_doc_sections.find(params[:id])
    return render json: { error: '默认板块不可删除' }, status: :unprocessable_entity if Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)

    section.destroy!
    head :ok
  end

  private

  def section_json(section)
    { id: section.id, name: section.name, department_ids: section.department_ids }
  end

  def manage_all?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def check_authorization
    authorize(Crm::DocSection)
  end
end
