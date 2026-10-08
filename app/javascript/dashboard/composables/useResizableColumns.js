import { ref, computed, onBeforeUnmount, toValue } from 'vue';

// 单据明细表的「像 Excel 那样拖列宽」。
// 金蝶就是表格式、列宽能拉——规格型号长的时候必须能拉宽才核得动料。
//
// 关键设计：**没拖过的列保持原来的 fr 自适应**，只有拖过的列才钉成固定像素。
// 一上来就全部换成固定像素的话，窗口一窄整张表就溢出被裁掉；保持 fr 则默认版式
// 与改造前完全一致，用户拉过哪一列才固定哪一列，其余列自动让位。
//
// cols: [{ key, label, fr }]，fr 为默认自适应份数；给 fixed 的列（序号/删除）永远不可拉。
// 拖完的宽度按 storageKey 存 localStorage，下次进来还是这个宽度。
const MIN_W = 40;

// cols 可以是数组，也可以是 ref/computed/getter——列序可拖的表格要用后者。
export function useResizableColumns(cols, storageKey) {
  const colList = () => toValue(cols);
  const resizable = colList().filter(c => c.fixed == null);

  const load = () => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
      // 只认还存在的列，且必须是正数——列改过名/删过之后不至于把表撑坏。
      return Object.fromEntries(
        resizable
          .map(c => [c.key, Number(saved?.[c.key])])
          .filter(([, v]) => v > 0)
      );
    } catch {
      return {};
    }
  };

  // { key: px }，只放「拖过的」列；没拖过的列不在里面，走 fr。
  const widths = ref(load());

  const persist = () => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(widths.value));
    } catch {
      // 隐身窗口/禁用站点数据时写不进去，拖动本身照常生效，只是下次不记得。
    }
  };

  const track = c => {
    if (c.fixed != null) return `${c.fixed}px`;
    const px = widths.value[c.key];
    // minmax：自适应的列也给个下限，免得别的列拉太宽后它被压成一条缝。
    return px ? `${px}px` : `minmax(${MIN_W}px, ${c.fr}fr)`;
  };

  const template = computed(() => colList().map(track).join(' '));

  let dragKey = null;
  let startX = 0;
  let startW = 0;

  const onMove = e => {
    if (!dragKey) return;
    widths.value[dragKey] = Math.max(MIN_W, startW + (e.clientX - startX));
  };

  const onUp = () => {
    if (!dragKey) return;
    dragKey = null;
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
    window.removeEventListener('mousemove', onMove);
    window.removeEventListener('mouseup', onUp);
    persist();
  };

  // e.currentTarget 是把手，它的父节点是表头格——起始宽度直接量当前渲染宽度，
  // 这样从 fr 切到固定像素时不会跳一下。
  const startResize = (key, e) => {
    const cell = e.currentTarget?.parentElement;
    dragKey = key;
    startX = e.clientX;
    startW = widths.value[key] || cell?.getBoundingClientRect().width || MIN_W;
    // 拖动过程中别让浏览器选中表头文字，光标全程保持成拉伸样式。
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  };

  // 全部放回自适应。
  const resetWidths = () => {
    widths.value = {};
    persist();
  };

  onBeforeUnmount(onUp);

  return { widths, template, startResize, resetWidths };
}
