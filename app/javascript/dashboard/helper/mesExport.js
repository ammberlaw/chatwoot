import { toJpeg } from 'html-to-image';
import * as XLSX from 'xlsx';

const safeName = n =>
  String(n || 'export')
    .replace(/[\\/:*?"<>|]/g, '_')
    .trim() || 'export';

const cell = v => (v === null || v === undefined ? '' : v);

// DOM 节点 → JPG 下载（用于打印/存档单据）。
export async function exportNodeToJpg(node, filename) {
  if (!node) return;
  const dataUrl = await toJpeg(node, {
    quality: 0.95,
    backgroundColor: '#ffffff',
    pixelRatio: 2,
    // 跳过标了 .export-skip 的节点（如导出按钮本身）。
    filter: n => !(n.classList && n.classList.contains('export-skip')),
  });
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = `${safeName(filename)}.jpg`;
  a.click();
}

// 结构化 { title, fields:[{label,value}], itemColumns:[{label,key}], items:[] } → Excel 下载。
export function exportDataToExcel(
  { title, fields = [], itemColumns = [], items = [] },
  filename
) {
  const aoa = [];
  if (title) aoa.push([title]);
  fields.forEach(f => aoa.push([f.label, cell(f.value)]));
  if (itemColumns.length) {
    aoa.push([]);
    aoa.push(itemColumns.map(c => c.label));
    items.forEach(row => aoa.push(itemColumns.map(c => cell(row[c.key]))));
  }
  const ws = XLSX.utils.aoa_to_sheet(aoa);
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
