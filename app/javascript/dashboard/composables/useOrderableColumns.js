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
 * @param {string[]} options.defaultHidden 这台机器第一次打开时默认收起的列。
 *        给列特别多的表用（应收待建账 31 列、横着要翻两屏半）：默认只摆常看的那些，
 *        其余在「列」面板里随时打开。只影响「从没调过列」的人，调过的按本机记录来。
 */
export function useOrderableColumns(
  defs,
  storageKey,
  { defaultHidden = [] } = {}
) {
  const defaultKeys = defs.map(c => c.key);
  const orderedKeys = ref([...defaultKeys]);
  const hiddenKeys = ref([]);
  const hiddenStorageKey = `${storageKey}.hidden`;

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

  // 收起的列。新增的列默认显示（不在这个表里就是显示），所以只需剔除已下线的 key。
  const loadHidden = () => {
    try {
      const raw = localStorage.getItem(hiddenStorageKey);
      // 从没调过列（本机没存过）→ 用默认收起名单；调过的一律按本机记录来，不去覆盖人家。
      if (raw === null) {
        hiddenKeys.value = defaultHidden.filter(k => defaultKeys.includes(k));
        return;
      }
      const saved = JSON.parse(raw || 'null');
      hiddenKeys.value = Array.isArray(saved)
        ? saved.filter(k => defaultKeys.includes(k))
        : [];
    } catch {
      hiddenKeys.value = [];
    }
  };
  loadHidden();

  const save = () => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(orderedKeys.value));
    } catch {
      // localStorage 不可用时忽略（本次会话内顺序仍生效）
    }
  };

  const saveHidden = () => {
    try {
      localStorage.setItem(hiddenStorageKey, JSON.stringify(hiddenKeys.value));
    } catch {
      // 同上
    }
  };

  const orderedColumns = computed(() =>
    orderedKeys.value.map(k => defs.find(c => c.key === k)).filter(Boolean)
  );

  /** 实际渲染用：按当前顺序，去掉收起的列。 */
  const visibleColumns = computed(() =>
    orderedColumns.value.filter(c => !hiddenKeys.value.includes(c.key))
  );

  const isHidden = key => hiddenKeys.value.includes(key);
  const toggleColumn = key => {
    hiddenKeys.value = isHidden(key)
      ? hiddenKeys.value.filter(k => k !== key)
      : [...hiddenKeys.value, key];
    saveHidden();
  };
  const showAllColumns = () => {
    hiddenKeys.value = [];
    saveHidden();
  };

  // ── 列宽：拖列头右边那条缝改宽窄，同样按人按表记在本机 ──────────────
  // 为什么要有：规格型号、备注这些列内容长短差很远，固定宽度不是挤成一条就是空一大片，
  // 各人核的东西不一样，宽度只能自己调（反馈点名）。
  const widthStorageKey = `${storageKey}.widths`;
  const widths = ref({});
  const MIN_COL_WIDTH = 48;

  const loadWidths = () => {
    try {
      const saved = JSON.parse(localStorage.getItem(widthStorageKey) || 'null');
      widths.value =
        saved && typeof saved === 'object'
          ? Object.fromEntries(
              Object.entries(saved).filter(
                ([k, v]) =>
                  defaultKeys.includes(k) && Number(v) >= MIN_COL_WIDTH
              )
            )
          : {};
    } catch {
      widths.value = {};
    }
  };
  loadWidths();

  const saveWidths = () => {
    try {
      localStorage.setItem(widthStorageKey, JSON.stringify(widths.value));
    } catch {
      // 同上
    }
  };

  /** 列头/单元格的宽度样式；没调过的列返回空对象，宽度仍由内容撑开。 */
  const colStyle = key => {
    const w = widths.value[key];
    // 三个都写死才拦得住 table 的自动布局——只给 width 时浏览器照样会按内容撑开。
    return w ? { width: `${w}px`, minWidth: `${w}px`, maxWidth: `${w}px` } : {};
  };

  const resizingKey = ref(null);
  const isResizing = key => resizingKey.value === key;

  /** 在列头右缘的把手上按下时调用，传入那个 th 元素。 */
  const startResize = (key, event, thEl) => {
    const startX = event.clientX;
    const startWidth = thEl?.getBoundingClientRect().width || MIN_COL_WIDTH;
    resizingKey.value = key;
    const onMove = e => {
      widths.value = {
        ...widths.value,
        [key]: Math.max(
          MIN_COL_WIDTH,
          Math.round(startWidth + e.clientX - startX)
        ),
      };
    };
    const onUp = () => {
      resizingKey.value = null;
      saveWidths();
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  };

  /** 双击把手：这一列恢复按内容自适应。 */
  const autoFitColumn = key => {
    const { [key]: _drop, ...rest } = widths.value;
    widths.value = rest;
    saveWidths();
  };

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

  /** 恢复默认列顺序，同时把收起的列都放出来。 */
  const resetOrder = () => {
    orderedKeys.value = [...defaultKeys];
    save();
    showAllColumns();
    // 列宽也一起清掉：「恢复默认列序」是一键回到出厂状态，留着调过的宽度等于没恢复。
    widths.value = {};
    saveWidths();
  };

  return {
    orderedColumns,
    visibleColumns,
    hiddenKeys,
    isHidden,
    toggleColumn,
    showAllColumns,
    isDragging,
    onColDragStart,
    onColDrop,
    resetOrder,
    colStyle,
    isResizing,
    startResize,
    autoFitColumn,
  };
}
