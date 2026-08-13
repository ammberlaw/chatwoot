import MesBomTemplateAPI from 'dashboard/api/mes/bomTemplates';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

// 模版明细以嵌套 bom_template_items_attributes 提交（后端 accepts_nested_attributes_for）。
export const useMesBomTemplatesStore = buildCrmStore({
  name: 'mesBomTemplates',
  API: MesBomTemplateAPI,
  paramKey: 'bom_template',
});
