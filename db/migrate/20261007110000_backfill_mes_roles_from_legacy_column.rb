# MES 角色两列并存的收尾：把遗留单值 account_users.mes_role 回填进多值 mes_roles。
#
# 背景：成员页早就改成多选、只写 mes_roles，但老成员的角色还留在单值列里——
# 生产上 9 人只有旧单值、1 人只有新多值。权限判断靠 effective_mes_roles 把两列并起来
# 才一直是对的；代价是「角色到底存在哪」要看人，排查权限问题时极易看漏一列
# （本次排查就先按 mes_roles 查出「全公司 0 个仓管」的错误结论）。
#
# 回填后 effective_mes_roles 只认 mes_roles，旧列进 ignored_columns 停止读写，
# 物理 DROP 留到下个版本——这次保留回滚余地：万一回退到备份镜像，
# 旧代码仍读 mes_role，两列此刻值相同，并集去重后行为一致。
class BackfillMesRolesFromLegacyColumn < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL.squish)
      UPDATE account_users
         SET mes_roles = ARRAY[mes_role]
       WHERE mes_role IS NOT NULL
         AND mes_role <> ''
         AND (mes_roles = '{}' OR mes_roles IS NULL)
    SQL
  end

  def down
    # 回填是幂等的补齐，不删数据：旧列原样还在，无需回退。
  end
end
