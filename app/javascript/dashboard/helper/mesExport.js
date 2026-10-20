import { toJpeg } from 'html-to-image';
import * as XLSX from 'xlsx';

const safeName = n =>
  String(n || 'export')
    .replace(/[\\/:*?"<>|]/g, '_')
    .trim() || 'export';

const cell = v => (v === null || v === undefined ? '' : v);

// 导出前把图片内联成 data URI。
//
// 为什么非做不可：附件实际存在对象存储上，ActiveStorage 的链接会 302 到那个域名。
// html-to-image 自己去抓图时跨域被挡，它**不报错、直接把这张图丢掉**——
// 导出来的就是一张「有版式没有图」的单据，业务附的产品图全不见了（反馈点名两次）。
// 这里走我们自己的同源请求带 cookie 抓一遍，抓不到的保持原样（最多还是那张丢图）。
const inlineImages = async node => {
  const imgs = Array.from(node.querySelectorAll('img[src]')).filter(
    img => !img.src.startsWith('data:')
  );
  const restore = [];
  await Promise.all(
    imgs.map(async img => {
      try {
        const res = await fetch(img.src, { credentials: 'include' });
        if (!res.ok) return;
        const blob = await res.blob();
        const dataUrl = await new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
        restore.push([img, img.src]);
        img.src = dataUrl;
      } catch {
        // 抓不到就算了：这张图导不出来，但不能因此让整张单据导出失败
      }
    })
  );
  return () =>
    restore.forEach(([img, src]) => {
      img.src = src;
    });
};

// 导出图片 = 发给车间的那一份。
//
// 两件事要在截图前处理掉：
//
// 1）标了 .export-secret 的节点隐藏。单价/金额/价源、采购注意事项、成本汇总这些
//    是给采购和财务看的，这张图要发到车间去。（.export-skip 是「任何导出都不要」，
//    比如导出按钮本身；.export-secret 只在导出图片时藏，页面上照常给有权限的人看。）
//
// 2）横向滚动的容器放开。明细表十几列靠 overflow-x 翻屏，截图只拿到可视区那几列，
//    物料后半段全丢（反馈原话「导出图片的内容，仅限鼠标停留的预览内容，物料后段的
//    内容看不见」）。把滚动容器连同外层节点一起撑成内容宽度，截完原样还原。
const SECRET_SELECTOR = '.export-secret';

const expandForShot = node => {
  const restore = [];
  const stash = (el, props) => {
    restore.push([el, props.map(k => [k, el.style[k]])]);
  };

  node.querySelectorAll(SECRET_SELECTOR).forEach(el => {
    stash(el, ['display']);
    el.style.display = 'none';
  });

  const scrollers = [node, ...node.querySelectorAll('*')].filter(el => {
    const cs = getComputedStyle(el);
    return (
      /(auto|scroll)/.test(cs.overflowX) || /(auto|scroll)/.test(cs.overflowY)
    );
  });
  scrollers.forEach(el => {
    stash(el, ['overflow', 'overflowX', 'overflowY', 'width', 'maxWidth']);
    el.style.overflow = 'visible';
    el.style.overflowX = 'visible';
    el.style.overflowY = 'visible';
    el.style.width = 'max-content';
    el.style.maxWidth = 'none';
  });

  // 最外层也要撑开：它的 offsetWidth 决定截图宽度，不放开还是按弹窗宽度裁。
  stash(node, ['width', 'maxWidth']);
  node.style.width = 'max-content';
  node.style.maxWidth = 'none';

  return () =>
    restore.forEach(([el, props]) =>
      props.forEach(([k, v]) => {
        el.style[k] = v || '';
      })
    );
};

// DOM 节点 → JPG 下载（用于打印/存档单据）。
export async function exportNodeToJpg(node, filename) {
  if (!node) return;
  const undo = await inlineImages(node);
  const collapse = expandForShot(node);
  const dataUrl = await toJpeg(node, {
    quality: 0.95,
    backgroundColor: '#ffffff',
    pixelRatio: 2,
    // 跳过标了 .export-skip 的节点（如导出按钮本身）。
    filter: n => !(n.classList && n.classList.contains('export-skip')),
  });
  collapse();
  undo();
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = `${safeName(filename)}.jpg`;
  a.click();
}

// 结构化 { title, fields:[{label,value}], itemColumns:[{label,key}], items:[] } → Excel 下载。
//
// 版式照着页面上的预览来：标题独占一行、抬头信息三组并排（像预览页那个信息块）、
// 底下才是用料明细表。原来是一行一个「标签 | 值」竖着铺几十行，明细表被挤到最下面，
// 车间拿到这份表看不懂（用户原话：「现在导出的电子档是这样的，生产觉得看不懂」，
// 「生产单的导出模板，能不能就是预览的这样？这样生产就能看懂了，我也不用同步做电子档了」）。
const HEADER_PAIRS_PER_ROW = 3; // 抬头每行放几组「标签+值」
const LONG_VALUE = 28; // 超过这个长度的值单独占一行（备注、颜色搭配这种）
const MIN_COLS = HEADER_PAIRS_PER_ROW * 2;

// 列宽：明细列按「表头字数 + 该列最长取值」估，夹在 8~46 之间。
// 不设宽的话规格型号那列全挤成一条缝，还是得手动拉——这正是被反馈的点。
const colWidths = (itemColumns, items, colCount) => {
  const widths = itemColumns.map(c => {
    const longest = items.reduce(
      (max, row) => Math.max(max, String(cell(row[c.key])).length),
      String(c.label).length
    );
    return { wch: Math.min(Math.max(longest + 2, 8), 46) };
  });
  while (widths.length < colCount) widths.push({ wch: 14 });
  return widths;
};

const pushHeaderRows = (aoa, merges, fields, colCount) => {
  let pending = [];
  const flush = () => {
    if (pending.length) aoa.push(pending.flat());
    pending = [];
  };
  fields
    .filter(f => cell(f.value) !== '')
    .forEach(f => {
      const value = String(cell(f.value));
      // 长文本单独成行并合并到整行宽，否则后面两组会被推到看不见的地方
      if (value.length > LONG_VALUE) {
        flush();
        const r = aoa.length;
        aoa.push([`${f.label}：`, value]);
        merges.push({ s: { r, c: 1 }, e: { r, c: colCount - 1 } });
        return;
      }
      pending.push([`${f.label}：`, value]);
      if (pending.length === HEADER_PAIRS_PER_ROW) flush();
    });
  flush();
};

export function exportDataToExcel(
  { title, fields = [], itemColumns = [], items = [], images = [] },
  filename
) {
  const aoa = [];
  const merges = [];
  const colCount = Math.max(itemColumns.length, MIN_COLS);

  if (title) {
    merges.push({
      s: { r: aoa.length, c: 0 },
      e: { r: aoa.length, c: colCount - 1 },
    });
    aoa.push([title]);
    aoa.push([]);
  }
  pushHeaderRows(aoa, merges, fields, colCount);

  // 附图：一张二维表塞不进图片本身，但至少要让人知道「附过几张、在哪」——
  // 原来导出的 Excel 里业务附的图连痕迹都没有，看的人以为根本没附（反馈点名）。
  // 要看图走「导出图片」或单据页面；这里给文件名和直链。
  if (images.length) {
    aoa.push([]);
    aoa.push([`附图（${images.length}）`, '链接']);
    images.forEach(img =>
      aoa.push([
        cell(img.filename),
        cell(img.url ? new URL(img.url, window.location.origin).href : ''),
      ])
    );
  }

  if (itemColumns.length) {
    aoa.push([]);
    aoa.push(itemColumns.map(c => c.label));
    items.forEach(row => aoa.push(itemColumns.map(c => cell(row[c.key]))));
  }

  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!merges'] = merges;
  ws['!cols'] = colWidths(itemColumns, items, colCount);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Sheet1');
  XLSX.writeFile(wb, `${safeName(filename)}.xlsx`);
}

// DOM 节点 → 直接打印：隐藏 iframe 复制单据内容 + 页面样式，调起系统打印对话框。
// 标了 .export-skip 的节点（操作按钮等）不进打印。
export function printNode(node, title) {
  if (!node) return;
  const iframe = document.createElement('iframe');
  Object.assign(iframe.style, {
    position: 'fixed',
    right: '0',
    bottom: '0',
    width: '0',
    height: '0',
    border: '0',
  });
  document.body.appendChild(iframe);

  const headStyles = Array.from(
    document.querySelectorAll('style, link[rel="stylesheet"]')
  )
    .map(el => el.outerHTML)
    .join('\n');
  const clone = node.cloneNode(true);
  clone.querySelectorAll('.export-skip').forEach(el => el.remove());

  const doc = iframe.contentDocument;
  doc.open();
  doc.write(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${safeName(title)}</title>${headStyles}` +
      '<style>body{background:#fff;margin:0;padding:16px}@page{margin:12mm}</style>' +
      `</head><body>${clone.outerHTML}</body></html>`
  );
  doc.close();

  // 等样式表/字体就绪再打印；打印后回收 iframe。
  setTimeout(() => {
    iframe.contentWindow.focus();
    iframe.contentWindow.print();
    setTimeout(() => iframe.remove(), 1500);
  }, 500);
}
