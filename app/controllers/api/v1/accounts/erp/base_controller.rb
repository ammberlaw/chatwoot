# ERP（财务管理）所有控制器的基类：统一「能否进入 ERP」门禁。
# 门禁：管理员/副管理员，或被赋予 erp_role 且 ERP 模块开关打开者可入；其他（含纯销售角色）一律 403。
# 生态硬约束：ERP 承载成本/供应商/毛利，销售端绝不可入。
# 后续切片的能力细分（应收/应付/出纳/凭证…）在各控制器内按 erp_can? 自行细校验，基类只管门禁。
class Api::V1::Accounts::Erp::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  include PaginationParamNormalizer

  before_action :ensure_erp_access

  private

  def ensure_erp_access
    return if Current.account_user&.can_access_erp?

    render json: { error: I18n.t('errors.erp.no_access', default: '无权访问财务 ERP') }, status: :forbidden
  end

  def page_param
    params[:page] || 1
  end

  # 前端可传 per_page（snake_case）加大每页条数；不传按默认 15。上限 100 防一把拉全表。
  def per_page_param
    params[:per_page].present? ? params[:per_page].to_i.clamp(1, 100) : RESULTS_PER_PAGE
  end

  # 冻结期闸（收付款单 update/void 共用）：给定日期里任何一个落在已结账期间就返回该期间号。
  def closed_period_for(*dates)
    dates.compact.map { |d| d.to_date.strftime('%Y-%m') }.uniq
         .find { |period| Erp::FiscalPeriod.closed?(Current.account, period) }
  end

  # 账龄分析的两个入参（应收/应付两个控制器共用）。
  def aging_as_of
    params[:as_of].presence&.to_date || Time.zone.today
  end

  def aging_basis
    params[:basis] == Erp::AgingService::INVOICE ? Erp::AgingService::INVOICE : Erp::AgingService::DUE
  end

  # 表头漏斗筛选（对标金蝶）：前端传 cf[<列>][op] / cf[<列>][value]。
  #
  # 在服务端筛，不在前端筛当前这一页——列表是分页的，只筛 50 行等于骗人：
  # 筛完说「没有」，翻到第二页它又在那儿。
  #
  # 只认调用方 map 里列出来的列（列名 → SQL 表达式）。map 之外的列一律忽略，
  # 所以前端哪几列画漏斗，必须和各控制器的 map 对齐（对不上＝漏斗点了没反应）。
  COLUMN_FILTER_OPS = {
    'contains' => ->(sql, v) { ["#{sql} ILIKE ?", "%#{v}%"] },
    'not_contains' => ->(sql, v) { ["COALESCE(#{sql}, '') NOT ILIKE ?", "%#{v}%"] },
    'eq' => ->(sql, v) { ["#{sql} = ?", v] },
    'ne' => ->(sql, v) { ["COALESCE(#{sql}, '') <> ?", v] },
    'starts' => ->(sql, v) { ["#{sql} ILIKE ?", "#{v}%"] },
    'ends' => ->(sql, v) { ["#{sql} ILIKE ?", "%#{v}"] },
    'blank' => ->(sql, _v) { ["COALESCE(#{sql}, '') = ''", nil] },
    'present' => ->(sql, _v) { ["COALESCE(#{sql}, '') <> ''", nil] }
  }.freeze
  # 值里的 % 和 _ 是用户打的字，不是通配符——不转义的话搜「50%」会把整表捞出来。
  LIKE_OPS = %w[contains not_contains starts ends].freeze

  def apply_column_filters(scope, column_sql)
    # cf 必须是嵌套 hash；传成别的（序列化出错、手工拼 URL）就当没筛，别把列表打成 500。
    filters = params[:cf].respond_to?(:to_unsafe_h) ? params[:cf].to_unsafe_h : {}
    filters.each do |key, spec|
      next unless spec.is_a?(Hash)

      clause = column_filter_clause(column_sql[key.to_s], spec['op'].to_s, spec['value'].to_s)
      next if clause.nil?

      condition, bind = clause
      scope = bind.nil? ? scope.where(Arel.sql(condition)) : scope.where(condition, bind)
    end
    scope
  end

  def column_filter_clause(sql, operator, value)
    handler = COLUMN_FILTER_OPS[operator]
    return nil if sql.blank? || handler.nil?

    like = LIKE_OPS.include?(operator)
    return nil if like && value.blank?

    handler.call(sql, like ? ActiveRecord::Base.sanitize_sql_like(value) : value)
  end
end
