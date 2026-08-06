import { ref, computed } from 'vue';
import OptionItemsAPI from 'dashboard/api/crm/optionItems';

// 客户分组 / 客户来源的可配置选项（二级层级）。模块级缓存，全站下拉共享；
// 设置页增删改后调 refresh(category) 让所有下拉与标签实时更新。
const items = {
  customer_group: ref([]),
  customer_source: ref([]),
};
const loaded = { customer_group: false, customer_source: false };

// 后端返回扁平有序列表（含 parent_id）→ 一级项 + 其下二级项的缩进下拉选项。
// 只取启用项；一级与二级均可被选中（存量客户存的是一级 code，保持兼容）。
const toOptions = list => {
  const active = list.filter(i => i.active);
  const roots = active.filter(i => !i.parent_id);
  const out = [];
  roots.forEach(root => {
    out.push({ value: root.code, label: root.name });
    active
      .filter(i => i.parent_id === root.id)
      .forEach(child =>
        out.push({ value: child.code, label: `  └ ${child.name}` })
      );
  });
  return out;
};

const labelFrom = (list, code) => {
  const hit = list.find(i => i.code === code);
  return hit ? hit.name : code || '';
};

export function useCrmOptions() {
  const load = async (category, { force = false } = {}) => {
    if (loaded[category] && !force) return;
    const { data } = await OptionItemsAPI.get(category);
    items[category].value = data.payload || [];
    loaded[category] = true;
  };

  const ensureLoaded = () =>
    Promise.all([load('customer_group'), load('customer_source')]);

  const refresh = category => load(category, { force: true });

  const groupOptions = computed(() => toOptions(items.customer_group.value));
  const sourceOptions = computed(() => toOptions(items.customer_source.value));
  const groupLabel = code => labelFrom(items.customer_group.value, code);
  const sourceLabel = code => labelFrom(items.customer_source.value, code);

  return {
    load,
    ensureLoaded,
    refresh,
    groupOptions,
    sourceOptions,
    groupLabel,
    sourceLabel,
  };
}
