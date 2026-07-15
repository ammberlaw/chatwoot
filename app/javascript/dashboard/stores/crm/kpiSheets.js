import CrmKpiSheetAPI from 'dashboard/api/crm/kpiSheets';
import { buildCrmStore } from './_crmStoreFactory';

// 列表 + 保存完成值/得分(update)。工作流动作(submit/score/确认)在详情页直接调 API。
export const useCrmKpiSheetsStore = buildCrmStore({
  name: 'crmKpiSheets',
  API: CrmKpiSheetAPI,
  paramKey: 'sheet',
});
