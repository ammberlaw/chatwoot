# Inherits from ActionController::Base to skip all middleware,
# authentication, and callbacks. Used for health checks
class HealthController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    # 带上版本号供前端比对：部署后页面一直开着的人跑的还是旧代码，看到的"没生效"
    # 其实是旧版（2026-10-09 排查出好几个"改了但没生效"都是这个）。前端轮询这里，
    # 发现版本变了就提示刷新。GIT_SHA 本来就随页面下发（window.globalConfig），不算新增暴露。
    render json: { status: 'woot', version: GIT_HASH }
  end
end
