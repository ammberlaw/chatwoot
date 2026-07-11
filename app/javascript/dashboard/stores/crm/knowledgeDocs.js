import CrmKnowledgeDocAPI from 'dashboard/api/crm/knowledgeDocs';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmKnowledgeDocsStore = buildCrmStore({
  name: 'crmKnowledgeDocs',
  API: CrmKnowledgeDocAPI,
  paramKey: 'doc',
});
