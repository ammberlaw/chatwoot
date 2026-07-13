import CrmKnowledgeCategoryAPI from 'dashboard/api/crm/knowledgeCategories';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmKnowledgeCategoriesStore = buildCrmStore({
  name: 'crmKnowledgeCategories',
  API: CrmKnowledgeCategoryAPI,
  paramKey: 'category',
});
