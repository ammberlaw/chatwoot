<script setup>
// ERP 板块布局壳：只承载 router-view，本身不做任何逻辑。
// erp-canvas 是「整页白卡」的挂钩层（与 MES 的 mes-canvas 同款，见 _next-colors.scss）：
// 经典灰主题下给内容区套白底圆角外框；紫玻璃默认主题下无样式 = 纯透传，不影响原布局。
</script>

<template>
  <div class="erp-canvas w-full h-full">
    <router-view />
  </div>
</template>
