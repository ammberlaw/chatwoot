<script setup>
import { computed } from 'vue';
import { STATUS_TONE, STATUS_VOID } from 'dashboard/helper/statusTone';

// MES 单据状态胶囊。配色直接取全站的 statusTone（别在这儿另起一套色，
// 否则同一个「草稿」在 CRM 和 MES 会是两种灰）。
//
// ⚠️ 按**状态文案**认档位，不按码值——同一个码值在各单据里意思不一样：
// 成品入库的 CANCELLED 显示「已取消」、生产领料的 CANCELLED 显示「已作废」，
// 而「已过账」在两处码值又恰好相同。各页的 STATUS_LABELS 已经把码值翻成了
// 统一的中文词，认那层就只需要维护这一张表；新单据沿用同样的词就自动有色，
// 认不出来的回落 idle 灰，不会渲染成没样式的裸字。
const props = defineProps({
  label: { type: String, default: '' },
});

const TONE_BY_LABEL = {
  草稿: 'idle',

  已下单: 'flow', // 单已发给供应商，在等货
  待出库: 'flow',
  部分已转: 'flow',

  待审批: 'busy',
  待审核: 'busy',
  待采购: 'busy',
  部分到货: 'busy', // 到了一部分，剩下的要盯
  进行中: 'busy',
  售后: 'busy',

  已到货: 'done',
  已过账: 'done',
  已出库: 'done',
  已出货: 'done',
  已转采购: 'done',
  已通过: 'done',
  已下发: 'done',
  在库: 'done',

  已完成: 'final',

  已终止: 'fail',
  已驳回: 'fail',
  已退回: 'fail',
};

// 作废档：MES 里「已取消」就是作废动作的结果（成品入库/原料入库按的是「作废」
// 按钮、状态却写作已取消），和生产领料的「已作废」是同一回事，必须同色——
// 所以这两个词都走 STATUS_VOID，不进 fail。
const VOID_LABELS = ['已作废', '已取消'];

const toneClass = computed(() => {
  if (VOID_LABELS.includes(props.label)) return STATUS_VOID;
  return STATUS_TONE[TONE_BY_LABEL[props.label]] || STATUS_TONE.idle;
});
</script>

<template>
  <span
    v-if="label"
    class="inline-flex items-center px-2 py-0.5 text-xs rounded-full whitespace-nowrap"
    :class="toneClass"
  >
    {{ label }}
  </span>
  <span v-else class="text-n-slate-10">—</span>
</template>
