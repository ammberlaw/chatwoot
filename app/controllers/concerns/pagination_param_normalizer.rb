# 分页参数容错：前端把 per_page 写成驼峰 perPage 时，后端读 params[:per_page] 读不到，
# 于是**静默回落到默认每页条数**——界面上看着就是「数据少了一截」，不报错、查不出来
# （商机列表与商机看板都栽过，两处现在靠源码注释提醒下一个人别写驼峰）。
# 靠注释防不住，在 CRM/MES/ERP 三个基类统一把驼峰折回下划线，从根上关掉这类静默截断。
module PaginationParamNormalizer
  extend ActiveSupport::Concern

  included do
    before_action :normalize_pagination_params
  end

  private

  def normalize_pagination_params
    return if params[:per_page].present?
    return if params[:perPage].blank?

    params[:per_page] = params[:perPage]
  end
end
