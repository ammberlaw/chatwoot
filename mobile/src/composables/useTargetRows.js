import { computed } from 'vue';
import { num } from '@/utils/format';

// 结转规则照搬网页端 CrmMyTargetIndex.vue：季度内逐月滚，每季度初（1/4/7/10 月）清零。
// 这是业务口径，两端必须完全一致，别在移动端另算一套。
export function useTargetRows(months, year) {
  const now = new Date();
  const nowYear = now.getFullYear();
  const nowMonth = now.getMonth();

  const rows = computed(() => {
    const src = months.value;
    if (!src.length) return [];
    const out = [];
    let cumBase = 0;
    let cumActual = 0;
    let cumBaseC = 0;
    let cumActualC = 0;
    for (let m = 0; m < 12; m += 1) {
      if (m % 3 === 0) {
        cumBase = 0;
        cumActual = 0;
        cumBaseC = 0;
        cumActualC = 0;
      }
      const row = src[m];
      const isFuture =
        year.value > nowYear || (year.value === nowYear && m > nowMonth);
      const carryAmount = isFuture ? 0 : cumBase - cumActual;
      const carryCount = isFuture ? 0 : cumBaseC - cumActualC;
      const baseAmount = num(row.base_amount_micros);
      const baseCount = num(row.base_count);
      out.push({
        month: m,
        baseAmount,
        baseCount,
        carryAmount,
        carryCount,
        effAmount: baseAmount + carryAmount,
        effCount: baseCount + carryCount,
        actualAmount: num(row.actual_amount_micros),
        actualCount: num(row.actual_count),
        hasActivity: baseAmount > 0 || baseCount > 0 || num(row.actual_count) > 0,
        isFuture,
      });
      cumBase += baseAmount;
      cumActual += num(row.actual_amount_micros);
      cumBaseC += baseCount;
      cumActualC += num(row.actual_count);
    }
    return out;
  });

  // 本季度至今累计（结转按季度清零，所以顶部看的是本季度整体达标）
  const quarter = computed(() => {
    const isCurrentYear = year.value === nowYear;
    const from = isCurrentYear ? Math.floor(nowMonth / 3) * 3 : 0;
    const upto = isCurrentYear ? nowMonth : 11;
    let base = 0;
    let actual = 0;
    for (let m = from; m <= upto; m += 1) {
      base += rows.value[m]?.baseAmount ?? 0;
      actual += rows.value[m]?.actualAmount ?? 0;
    }
    return { base, actual, index: Math.floor(from / 3) + 1 };
  });

  // 有效目标 ≤ 0（结余已覆盖）视为达成
  const pct = (actual, effTarget) => {
    if (effTarget <= 0) return actual >= 0 ? 100 : null;
    return (actual / effTarget) * 100;
  };

  const barClass = p => {
    if (p == null) return 'bg-[color:var(--pb-fill)]';
    // 只分两态：达标高亮成品牌黄，其余一律黑。
    // 百分比数字已经把「差多少」说清楚了，条子的职责是长度不是色相。
    return p >= 100 ? 'bg-[color:var(--pb-brand)]' : 'bg-[color:var(--pb-ink)]';
  };

  return { rows, quarter, pct, barClass, nowYear, nowMonth };
}
