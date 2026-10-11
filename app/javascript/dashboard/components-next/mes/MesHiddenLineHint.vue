<script setup>
// 「产线为空被隐藏」提示条。
//
// 产线分流是 where(product_line = 当前产线)，没设产线的单据在任何一条具体产线下都查不到，
// 页面上和「数据丢了」长得一模一样（BOM、BOM 模版都这么丢过）。后端在列表 meta 里回
// hidden_no_line，这里把它摆出来，并告诉人去哪看。
// 条数为 0 时由调用方 v-if 掉，不渲染空壳。
defineProps({
  count: { type: Number, required: true },
  // 单位量词：条 / 份 / 张 / 种，按所在列表的说法来。
  unit: { type: String, default: '条' },
});
</script>

<template>
  <div
    class="p-3 mb-3 text-sm border rounded-lg border-n-amber-8 bg-n-amber-3 text-n-amber-11"
  >
    当前产线下有 {{ count }}
    {{ unit }}未设产线的记录没有显示，切到「全部产线」可以看到。
  </div>
</template>
