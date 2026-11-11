import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

// 🔴 `_destroy` 必须原样送到后端：snakecase-keys 默认会把前导下划线吃掉（`_destroy` → `destroy`），
// Rails 的 accepts_nested_attributes_for 收不到删除标记，于是「明细行点了 X、保存后还在」。
// 所有带嵌套明细的单据（采购单/BOM/凭证…）都走这里，统一在转换时排除这个键。
const toSnake = fields =>
  snakecaseKeys(fields, { deep: true, exclude: ['_destroy'] });

const normalizeMeta = meta => ({
  ...camelcaseKeys(meta || {}),
  count: Number(meta?.count || 0),
  currentPage: Number(meta?.current_page || meta?.currentPage || 1),
});

// 不同列表视图共用同一份 records；旧请求的成功、错误和收尾都不能覆盖新请求。
const latestListRequests = new WeakMap();
export const fetchCrmList = async (store, load) => {
  const request = {};
  latestListRequests.set(store, request);
  store.setUIFlag({ fetchingList: true });
  try {
    const { data } = await load();
    if (latestListRequests.get(store) !== request) return store.records;

    store.records = camelize(data.payload);
    store.meta = normalizeMeta(data.meta);
    return store.records;
  } catch (error) {
    if (latestListRequests.get(store) !== request) return store.records;

    return throwErrorMessage(error);
  } finally {
    if (latestListRequests.get(store) === request) {
      store.setUIFlag({ fetchingList: false });
    }
  }
};

// CRM 资源通用 Pinia store：list/create/update/delete，payload 按 paramKey 包装。
export const buildCrmStore = ({ name, API, paramKey, extraActions }) =>
  createStore({
    name,
    type: 'pinia',
    API,
    getters: {
      getRecords: state => state.records,
    },
    actions: () => ({
      get(params = {}) {
        return fetchCrmList(this, () => API.get(params));
      },

      // 「分发给我的」列表：走 API.distributed（仅邮件 store 用）；载入格式与 get 一致。
      getDistributed(params = {}) {
        return fetchCrmList(this, () => API.distributed(params));
      },

      // 「我分发的」列表：走 API.distributedByMe（主管/管理员，仅邮件 store 用）。
      getDistributedByMe(params = {}) {
        return fetchCrmList(this, () => API.distributedByMe(params));
      },

      async create(obj) {
        this.setUIFlag({ creatingItem: true });
        try {
          // __files 存在时用 multipart 一次性带附件创建（如销售订单要求 PI 附件）。
          const { __files: files, ...fields } = obj;
          let data;
          if (files && files.length) {
            const snake = toSnake(fields);
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
              [paramKey]: toSnake(fields),
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
            [paramKey]: toSnake(rest),
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

      // 额外动作（如 MES 单据「退回上一环节 / 重新激活」）：函数式 API=>({...})，
      // 闭包拿 API、this 绑定 store。不传则无。
      ...(extraActions ? extraActions(API) : {}),
    }),
  });
