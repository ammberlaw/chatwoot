import MesBomAPI from 'dashboard/api/mes/boms';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

// BOM 明细以嵌套 bom_items_attributes 提交（后端 accepts_nested_attributes_for）。
export const useMesBomsStore = buildCrmStore({
  name: 'mesBoms',
  API: MesBomAPI,
  paramKey: 'bom',
});
