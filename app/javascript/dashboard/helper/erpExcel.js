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

// 分页接口的全量拉取。上面第 2 条规矩的落地件：台账类列表屏幕上一页只有 50 条，
// 直接拿 rows 去导就是导了一页。ERP 后端把 per_page 夹在 100 以内（见 Erp::BaseController），
// 所以只能一页页要，按 meta.count 收口。
//
// fetchPage 收一个参数对象、返回 axios 响应（{ data: { payload, meta } }）。
export async function fetchAllRows(fetchPage, params = {}, options = {}) {
  const perPage = options.perPage || 100;
  // 兜底上限：接口要是把 count 报错了，别让前端无限翻页把浏览器卡死。
  const maxRows = options.maxRows || 20000;
  const rows = [];
  let page = 1;
  let total = Infinity;
  while (rows.length < total && rows.length < maxRows) {
    // eslint-disable-next-line no-await-in-loop
    const { data } = await fetchPage({ ...params, page, per_page: perPage });
    const chunk = data?.payload || [];
    rows.push(...chunk);
    total = Number(data?.meta?.count ?? rows.length);
    if (chunk.length < perPage) break;
    page += 1;
  }
  return rows;
}

const safeName = name =>
  String(name || 'export')
    .replace(/[\\/:*?"<>|]/g, '_')
    .trim() || 'export';

// micros → Excel 数值；空值给空单元格，别写成 0（「没有」和「零」在账上不是一回事）。
export const microsToYuan = micros =>
  micros === null || micros === undefined
    ? ''
    : Number((Number(micros) / YUAN).toFixed(2));

// 后端的 decimal 字段（数量、汇率、税率…）序列化成**字符串**：'50.0'、'7.15'。
// 直接写进 Excel 就是一列文本，财务求和/透视全是 #VALUE!。标 num 的列统一转数值；
// 空值仍留空（「没有」和「零」在账上不是一回事），转不动的原样放回。
const toNumberCell = value => {
  if (value === null || value === undefined || value === '') return '';
  const n = Number(value);
  return Number.isNaN(n) ? value : n;
};

const cellOf = (row, column) => {
  const raw = row[column.key];
  if (column.money) return microsToYuan(raw);
  if (column.num) return toNumberCell(raw);
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
