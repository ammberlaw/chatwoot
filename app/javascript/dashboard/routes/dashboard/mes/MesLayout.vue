<script setup>
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

// MES 板块布局壳：仅承载 router-view，并以当前产品线为 key。
// 切换产品线时，当前 MES 页组件重挂（重跑 onMounted 拉取，请求经 axios 拦截带新线），
// 从而整站 MES 页按线过滤——只重挂这一个页，不刷新整个应用。
const { activeProductLine } = useMesProductLine();
</script>

<template>
  <router-view :key="`mes-${activeProductLine || 'all'}`" />
</template>
