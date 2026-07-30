import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

const normalizeMeta = meta => ({
  ...camelcaseKeys(meta || {}),
  count: Number(meta?.count || 0),
  currentPage: Number(meta?.current_page || meta?.currentPage || 1),
});

// CRM 资源通用 Pinia store：list/create/update/delete，payload 按 paramKey 包装。
// extraActions：可选，(API) => ({...actions}) 追加自定义动作（如 MES 单据退回）。
export const buildCrmStore = ({ name, API, paramKey, extraActions }) =>
  createStore({
    name,
    type: 'pinia',
    API,
    getters: {
      getRecords: state => state.records,
    },
    actions: () => ({
      ...(extraActions ? extraActions(API) : {}),
      async get(params = {}) {
        this.setUIFlag({ fetchingList: true });
        try {
          const { data } = await API.get(params);
          this.records = camelize(data.payload);
          this.meta = normalizeMeta(data.meta);
          return this.records;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.setUIFlag({ fetchingList: false });
        }
      },

      async create(obj) {
        this.setUIFlag({ creatingItem: true });
        try {
          // __files 存在时用 multipart 一次性带附件创建（如销售订单要求 PI 附件）。
          const { __files: files, ...fields } = obj;
          let data;
          if (files && files.length) {
            const snake = snakecaseKeys(fields, { deep: true });
            const fd = new FormData();
            Object.entries(snake).forEach(([key, value]) => {
              if (value !== null && value !== undefined) {
                fd.append(`${paramKey}[${key}]`, value);
              }
            });
            files.forEach(f => fd.append(`${paramKey}[files][]`, f));
            ({ data } = await API.createWithFiles(fd));
          } else {
            ({ data } = await API.create({
              [paramKey]: snakecaseKeys(fields, { deep: true }),
            }));
          }
          const record = camelize(data);
          this.records.unshift(record);
          return record;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.setUIFlag({ creatingItem: false });
        }
      },

      async update({ id, ...rest }) {
        this.setUIFlag({ updatingItem: true });
        try {
          const { data } = await API.update(id, {
            [paramKey]: snakecaseKeys(rest, { deep: true }),
          });
          const record = camelize(data);
          const index = this.records.findIndex(r => r.id === record.id);
          if (index !== -1) this.records[index] = record;
          return record;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.setUIFlag({ updatingItem: false });
        }
      },

      async delete(id) {
        this.setUIFlag({ deletingItem: true });
        try {
          await API.delete(id);
          this.records = this.records.filter(r => r.id !== id);
          return id;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.setUIFlag({ deletingItem: false });
        }
      },
    }),
  });
