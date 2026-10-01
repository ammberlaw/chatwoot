import { computed, ref } from 'vue';

/**
 * 表头拖拽重排，顺序按人按表记在本机。
 *
 * 用原生 HTML5 DnD 而不是 vuedraggable：后者对 <tr> 下混排的 <th>/<td> 支持不好。
 *
 * 用法：
 *   const { orderedColumns, isDragging, onColDragStart, onColDrop } =
 *     useOrderableColumns(COLUMN_DEFS, 'mesBomCols.v1');
 * 表头 v-for="col in orderedColumns" 挂上 draggable / @dragstart / @dragover.prevent / @drop，
 * 单元格同样 v-for="col in orderedColumns"，内部按 col.key 分支。
 *
 * @param {Array<{key:string}>} defs 列定义（key 必须稳定，改了等于新列）
 * @param {string} storageKey 本机存储键；多人共用一台机器时自行带上用户 id
 */
export function useOrderableColumns(defs, storageKey) {
  const defaultKeys = defs.map(c => c.key);
  const orderedKeys = ref([...defaultKeys]);

  // 剔除已下线的列、补齐新增的列（新列排末尾）——否则加一列后老用户永远看不到它。
  const load = () => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || 'null');
      if (Array.isArray(saved)) {
        const kept = saved.filter(k => defaultKeys.includes(k));
        orderedKeys.value = [
          ...kept,
          ...defaultKeys.filter(k => !kept.includes(k)),
        ];
        return;
      }
    } catch {
      // 解析失败回落默认顺序
    }
    orderedKeys.value = [...defaultKeys];
  };
  load();

  const save = () => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(orderedKeys.value));
    } catch {
      // localStorage 不可用时忽略（本次会话内顺序仍生效）
    }
  };

  const orderedColumns = computed(() =>
    orderedKeys.value.map(k => defs.find(c => c.key === k)).filter(Boolean)
  );

  const dragColKey = ref(null);
  const isDragging = key => dragColKey.value === key;
  const onColDragStart = key => {
    dragColKey.value = key;
  };
  const onColDrop = targetKey => {
    const from = dragColKey.value;
    dragColKey.value = null;
    if (!from || from === targetKey) return;
    const arr = [...orderedKeys.value];
    const fromIdx = arr.indexOf(from);
    const toIdx = arr.indexOf(targetKey);
    if (fromIdx < 0 || toIdx < 0) return;
    arr.splice(fromIdx, 1);
    arr.splice(toIdx, 0, from);
    orderedKeys.value = arr;
    save();
  };

  /** 恢复默认列顺序。 */
  const resetOrder = () => {
    orderedKeys.value = [...defaultKeys];
    save();
  };

  return { orderedColumns, isDragging, onColDragStart, onColDrop, resetOrder };
}
