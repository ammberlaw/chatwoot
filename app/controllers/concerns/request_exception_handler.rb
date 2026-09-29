module RequestExceptionHandler
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  end

  private

  def handle_with_exception
    yield
  rescue ActiveRecord::RecordNotFound => e
    log_handled_error(e)
    render_not_found_error('Resource could not be found')
  rescue Pundit::NotAuthorizedError => e
    log_handled_error(e)
    # 权限不足是 403 不是 401：401 的语义是「你没登录/登录态无效」。
    # 混用的后果很实在——侧边栏轮询 MES 审批箱，财务没出库权限收到 401，
    # 前端按「掉登录」处理就会把正常登录的人踢出去；运维看日志也会把权限问题
    # 误判成认证故障（生产一天上百条 401 全是这么来的）。
    render_forbidden('You are not authorized to do this action')
  rescue ActionController::ParameterMissing => e
    log_handled_error(e)
    render_could_not_create_error(e.message)
  ensure
    # to address the thread variable leak issues in Puma/Thin webserver
    Current.reset
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end

  # 已登录但没权限。render_unauthorized（401）留给认证类失败：无 token、token 失效、账号被停用。
  def render_forbidden(message)
    render json: { error: message }, status: :forbidden
  end

  def render_not_found_error(message)
    render json: { error: message }, status: :not_found
  end

  def render_could_not_create_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def render_payment_required(message)
    render json: { error: message }, status: :payment_required
  end

  def render_internal_server_error(message)
    render json: { error: message }, status: :internal_server_error
  end

  def render_record_invalid(exception)
    log_handled_error(exception)
    render json: {
      message: exception.record.errors.full_messages.join(', '),
      attributes: exception.record.errors.attribute_names
    }, status: :unprocessable_entity
  end

  def render_error_response(exception)
    log_handled_error(exception)
    render json: exception.to_hash, status: exception.http_status
  end

  def log_handled_error(exception)
    logger.info("Handled error: #{exception.inspect}")
  end
end
