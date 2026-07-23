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
