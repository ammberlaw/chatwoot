<script setup>
// 三联复写纸票面的外壳（采购入库单 / 销售出库单共用）。
// 公司实际用针式打印机套打 9.5×5.5 英寸三联纸：存根白联 / 客户红联 / 财务黄联，
// 联次是竖排印在纸的最右边那一条上的——不是一行文字，位置错了就压到预印格线上。
//
// 版心宽度按 9.5 英寸减去左右边距定死，不跟着屏幕走：套打的东西一缩放就对不准。
defineProps({
  title: { type: String, required: true },
});
const PLIES = ['一 存根白联', '二 客户红联', '三 财务黄联'];
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- 票面必须内联样式：printElement 只把白名单计算样式内联进克隆，靠 class 的边框/列宽会丢。 -->
<template>
  <div
    class="mes-print-sheet"
    style="
      display: flex;
      align-items: stretch;
      gap: 8px;
      width: 880px;
      color: #000;
      font-family: 'Songti SC', 'SimSun', serif;
      font-size: 12px;
    "
  >
    <div style="flex: 1; min-width: 0">
      <slot name="header" />
      <div
        style="
          text-align: center;
          font-size: 19px;
          font-weight: 700;
          letter-spacing: 6px;
          border-bottom: 1px solid #000;
          width: 240px;
          margin: 0 auto 8px;
          padding-bottom: 2px;
        "
      >
        {{ title }}
      </div>
      <slot />
    </div>

    <!-- 右侧竖排联次 -->
    <div
      style="
        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
        width: 18px;
        font-size: 11px;
        line-height: 1.1;
      "
    >
      <span
        v-for="ply in PLIES"
        :key="ply"
        style="writing-mode: vertical-rl; letter-spacing: 2px"
      >
        {{ ply }}
      </span>
    </div>
  </div>
</template>
