/* global axios */

// CRM「业务员」下拉数据源：只返回 CRM 成员，按可见范围收口。
// scope='team' 走 CRM 团队口径（销售订单），省略则走部门口径（客户/商机等）。
export default {
  get(accountId, scope) {
    return axios.get(`/api/v1/accounts/${accountId}/crm/agents`, {
      params: scope ? { scope } : {},
    });
  },
};
