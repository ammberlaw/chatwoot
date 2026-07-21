import MesProductionRecordAPI from 'dashboard/api/mes/productionRecords';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesProductionRecordsStore = buildCrmStore({
  name: 'mesProductionRecords',
  API: MesProductionRecordAPI,
  paramKey: 'production_record',
});
