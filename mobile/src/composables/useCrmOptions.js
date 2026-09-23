import { ref, computed } from 'vue';
import { fetchOptionItems } from '@/api/crm';

// 客户分组 / 客户来源是后台可配置项（Crm::OptionItem，二级层级），不是硬编码枚举。
// 与网页端 dashboard/composables/useCrmOptions.js 同口径：模块级缓存，全 App 共享。
const items = { customer_group: ref([]), customer_source: ref([]), product_group: ref([]) };
const loaded = { customer_group: false, customer_source: false, product_group: false };

// 扁平有序列表（含 parent_id）→ 一级项 + 缩进的二级项。一级二级均可选中
// （存量客户存的是一级 code）。
const toOptions = list => {
  const active = list.filter(i => i.active);
  const out = [];
  active
    .filter(i => !i.parent_id)
    .forEach(root => {
      out.push({ value: root.code, label: root.name });
      active
        .filter(i => i.parent_id === root.id)
        .forEach(c => out.push({ value: c.code, label: `　└ ${c.name}` }));
    });
  return out;
};

const labelFrom = (list, code) =>
  list.find(i => i.code === code)?.name || code || '';

export function useCrmOptions() {
  const load = async category => {
    if (loaded[category]) return;
    try {
      const r = await fetchOptionItems(category);
      items[category].value = r.data?.payload || [];
      loaded[category] = true;
    } catch {
      // 断网时下拉留空，不阻塞表单其余字段
    }
  };

  return {
    ensureLoaded: () =>
      Promise.all([load('customer_group'), load('customer_source'), load('product_group')]),
    groupOptions: computed(() => toOptions(items.customer_group.value)),
    sourceOptions: computed(() => toOptions(items.customer_source.value)),
    productGroupOptions: computed(() => toOptions(items.product_group.value)),
    groupLabel: code => labelFrom(items.customer_group.value, code),
    sourceLabel: code => labelFrom(items.customer_source.value, code),
  };
}
