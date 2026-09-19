// ERP 列表导出 Excel。
//
// ⚠️ 两条规矩，破了导出就是废的：
// 1. **金额导成数值，不是带千分位的字符串**。财务打开表第一件事就是求和、做透视，
//    一列文本型「¥1,234.00」在 Excel 里什么都算不了。
// 2. **导出必须是全量**，不是屏幕上那一页。毛利/账簿这类页面后端有截断，
//    导出前得先向后端要全量——「只导了 200 行」还显示导出成功，比不给导出更糟。
//    这条由调用方保证，本文件只负责把给到的行写成表。
import * as XLSX from 'xlsx';

const YUAN = 1_000_000;

const safeName = name =>
  String(name || 'export')
    .replace(/[\\/:*?"<>|]/g, '_')
    .trim() || 'export';

// micros → Excel 数值；空值给空单元格，别写成 0（「没有」和「零」在账上不是一回事）。
export const microsToYuan = micros =>
  micros === null || micros === undefined
    ? ''
    : Number((Number(micros) / YUAN).toFixed(2));

const cellOf = (row, column) => {
  const raw = row[column.key];
  if (column.money) return microsToYuan(raw);
  return raw === null || raw === undefined ? '' : raw;
};

// 列宽按「表头 + 前 200 行内容」里最宽的那个估，中文按两个字符宽算。
const widthOf = (column, rows) => {
  const width = value =>
    String(value ?? '').replace(/[^\x20-\x7E]/g, '00').length;
  const body = rows.slice(0, 200).map(row => width(cellOf(row, column)));
  return { wch: Math.min(Math.max(width(column.label), ...body, 8) + 2, 40) };
};

/**
 * { title, meta:[{label,value}], columns:[{label,key,money}], rows } → .xlsx 下载。
 * meta 是表头上的自解释信息（期间、筛选条件、口径说明）——没有它，
 * 导出的表过两天没人说得清是哪个月、哪个口径的数。
 */
export function exportRowsToExcel(
  { title, meta = [], columns = [], rows = [] },
  filename
) {
  const aoa = [];
  if (title) aoa.push([title]);
  meta.forEach(item => aoa.push([item.label, item.value ?? '']));
  if (aoa.length) aoa.push([]);
  aoa.push(columns.map(column => column.label));
  rows.forEach(row => aoa.push(columns.map(column => cellOf(row, column))));

  const sheet = XLSX.utils.aoa_to_sheet(aoa);
  sheet['!cols'] = columns.map(column => widthOf(column, rows));
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, sheet, 'Sheet1');
  XLSX.writeFile(book, `${safeName(filename)}.xlsx`);
}
