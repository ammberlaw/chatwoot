import MesProductionRecordAPI from 'dashboard/api/mes/productionRecords';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';
import { buildMesReturnActions } from './_returnActions';

export const useMesProductionRecordsStore = buildCrmStore({
  name: 'mesProductionRecords',
  API: MesProductionRecordAPI,
  paramKey: 'production_record',
  extraActions: buildMesReturnActions,
});
