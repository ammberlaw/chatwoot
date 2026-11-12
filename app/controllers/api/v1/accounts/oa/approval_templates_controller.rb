class Api::V1::Accounts::Oa::ApprovalTemplatesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:update, :destroy]

  def index
    scope = Current.account.oa_approval_templates.ordered
    scope = scope.active if params[:active] == 'true'
    @templates = scope
  end

  def create
    @template = Current.account.oa_approval_templates.create!(template_params)
  end

  def update
    @template.with_lock { @template.update!(template_params) }
  end

  def destroy
    archived = false
    @template.with_lock do
      if @template.requests.exists?
        @template.update!(active: false)
        archived = true
      else
        @template.destroy!
      end
    end
    render json: { archived: archived }
  end

  private

  def fetch_template
    @template = Current.account.oa_approval_templates.find(params[:id])
  end

  def check_authorization
    authorize(Oa::ApprovalTemplate)
  end

  def template_params
    permitted = params.require(:template).permit(
      :name, :description, :icon, :active, :position, :attendance_kind, :cash_kind, :erp_expense, :auto_approve, :overdue_hours,
      form_fields: [:key, :label, :type, :required, { options: [] }],
      cc_user_ids: []
    )
    # 必须落成纯 hash 再并 flow：并进 Parameters 的话，取回来的嵌套节点是「未许可」的
    # Parameters，写 jsonb 时 to_h 会抛 UnfilteredParameters。
    raw_flow = params[:template][:flow]
    attrs = permitted.to_h
    raw_flow.nil? ? attrs : attrs.merge('flow' => sanitize_flow(raw_flow))
  end

  # flow 是递归结构（条件分支的 flow 里还能再放条件分支），strong params 的声明式白名单
  # 表达不了递归——写成 flow: [:type, :user_id] 会把 branches 整个丢掉、条件分支存不进去。
  # 所以这里按节点类型逐层重建，只保留认识的 key。
  def sanitize_flow(nodes)
    to_list(nodes).filter_map { |node| sanitize_node(node) }
  end

  def sanitize_node(node)
    step = to_hash(node)
    return nil if step.blank?
    return sanitize_condition(step) if step[:type] == 'condition'
    return nil unless Oa::ApprovalTemplate::STEP_TYPES.include?(step[:type])

    { 'type' => step[:type], 'user_id' => step[:user_id].presence&.to_i }
  end

  def sanitize_condition(step)
    { 'type' => 'condition', 'branches' => to_list(step[:branches]).filter_map { |b| sanitize_branch(b) } }
  end

  def sanitize_branch(branch)
    b = to_hash(branch)
    return nil if b.blank?

    { 'auto_approve' => ActiveModel::Type::Boolean.new.cast(b[:auto_approve]),
      'conditions' => to_list(b[:conditions]).filter_map { |c| sanitize_condition_row(c) },
      'flow' => sanitize_flow(b[:flow]) }
  end

  # 条件值：发起人属于是 ["dept:1","user:9"] 多选，其余是单值（数字/文本原样留）。
  def sanitize_condition_row(cond)
    c = to_hash(cond)
    return nil if c.blank?

    value = c[:value]
    value = to_list(value).map(&:to_s) if value.is_a?(Array)
    { 'var' => c[:var].to_s, 'op' => c[:op].to_s, 'value' => value }
  end

  def to_list(value) = value.is_a?(Array) ? value : []

  def to_hash(value)
    h = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    h.is_a?(Hash) ? h.with_indifferent_access : nil
  end
end
