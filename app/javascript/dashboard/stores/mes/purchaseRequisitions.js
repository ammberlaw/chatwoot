import MesPurchaseRequisitionAPI from 'dashboard/api/mes/purchaseRequisitions';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

// 请购单明细以嵌套 requisition_items_attributes 提交（后端 accepts_nested_attributes_for）。
export const useMesPurchaseRequisitionsStore = buildCrmStore({
  name: 'mesPurchaseRequisitions',
  API: MesPurchaseRequisitionAPI,
  paramKey: 'purchase_requisition',
});
