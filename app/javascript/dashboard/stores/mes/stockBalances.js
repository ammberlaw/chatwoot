import MesStockBalanceAPI from 'dashboard/api/mes/stockBalances';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

// 结存只读列表（后端 index 返回 payload，无分页 meta）。
export const useMesStockBalancesStore = buildCrmStore({
  name: 'mesStockBalances',
  API: MesStockBalanceAPI,
  paramKey: 'stock_balance',
});
