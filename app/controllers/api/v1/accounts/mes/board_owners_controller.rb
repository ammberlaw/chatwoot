# MES 阶段板块负责人：index 全员可读（业务要知道各阶段找谁）；set 仅管理员/副管理员配置。
class Api::V1::Accounts::Mes::BoardOwnersController < Api::V1::Accounts::Mes::BaseController
  def index
    owners = Current.account.mes_board_owners.index_by(&:board_key)
    names = user_names_for(owners.values.flat_map(&:manager_ids))
    render json: {
      payload: owners.map do |board_key, owner|
        board_owner_json(board_key, owner.manager_ids, names)
      end
    }
  end

  def set
    return render json: { error: '无权限设置负责人' }, status: :forbidden unless manage_all?

    board_key = params[:board_key].to_s.strip
    return render json: { error: '板块标识不能为空' }, status: :unprocessable_entity if board_key.blank?

    owner = Current.account.mes_board_owners.find_or_initialize_by(board_key: board_key)
    owner.update!(manager_ids: sanitized_member_ids)
    render json: board_owner_json(owner.board_key, owner.manager_ids, user_names_for(owner.manager_ids))
  end

  private

  def board_owner_json(board_key, manager_ids, names)
    {
      board_key: board_key,
      manager_ids: manager_ids,
      manager_names: manager_ids.filter_map { |id| names[id] }
    }
  end

  # 仅接受本账号成员的 user_id，保序去重。
  def sanitized_member_ids
    ids = Array(params[:manager_ids]).map(&:to_i).uniq
    valid = Current.account.account_users.where(user_id: ids).pluck(:user_id).to_set
    ids.select { |id| valid.include?(id) }
  end

  def user_names_for(ids)
    User.where(id: ids.uniq).pluck(:id, :name).to_h
  end

  def manage_all?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end
end
