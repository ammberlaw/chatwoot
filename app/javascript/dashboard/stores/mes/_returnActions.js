import camelcaseKeys from 'camelcase-keys';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const replace = (records, record) => {
  const index = records.findIndex(r => r.id === record.id);
  if (index !== -1) records[index] = record;
};

// 单据「退回上一环节 / 重新激活」的通用 Pinia 动作，各 MES 单据 store 复用。
export const buildMesReturnActions = API => ({
  async returnDocument(id, reason) {
    this.setUIFlag({ updatingItem: true });
    try {
      const { data } = await API.returnDocument(id, reason);
      const record = camelize(data);
      replace(this.records, record);
      return record;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      this.setUIFlag({ updatingItem: false });
    }
  },

  async reactivate(id) {
    this.setUIFlag({ updatingItem: true });
    try {
      const { data } = await API.reactivate(id);
      const record = camelize(data);
      replace(this.records, record);
      return record;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      this.setUIFlag({ updatingItem: false });
    }
  },
});
