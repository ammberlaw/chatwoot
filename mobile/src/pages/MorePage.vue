<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import AppSheet from '@/components/AppSheet.vue';
import { useAuthStore } from '@/stores/auth';
import { MODULE_GROUPS } from '@/constants/modules';

defineOptions({ name: 'MorePage' });

const router = useRouter();
const auth = useAuthStore();
const confirmLogout = ref(false);

// 只列路由里真实存在的模块，避免清单先行、页面后到时点出死链
const groups = computed(() =>
  MODULE_GROUPS.map(g => ({
    ...g,
    items: g.items.filter(i => router.hasRoute(i.name)),
  })).filter(g => g.items.length)
);

const logout = async () => {
  await auth.logout();
  router.replace({ name: 'login' });
};
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="更多" />

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <!-- 账号 -->
      <div class="flex items-center gap-3 p-4 wt-card">
        <span
          class="grid flex-none text-base font-semibold rounded-full size-11 place-items-center bg-[color:var(--pb-fill)] text-[color:var(--pb-accent)]"
        >
          {{ (auth.user?.name || auth.user?.email || '?').trim().charAt(0).toUpperCase() }}
        </span>
        <div class="flex-1 min-w-0">
          <div class="font-semibold truncate text-[color:var(--pb-ink)]">
            {{ auth.user?.name || '未命名' }}
          </div>
          <div class="mt-0.5 text-xs truncate text-[color:var(--pb-ink-3)]">{{ auth.user?.email }}</div>
        </div>
      </div>

      <template v-for="g in groups" :key="g.title">
        <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-[color:var(--pb-ink-3)]">
          {{ g.title }}
        </h2>
        <ul class="overflow-hidden wt-card">
          <li v-for="item in g.items" :key="item.name">
            <button
              type="button"
              class="flex items-center w-full gap-3 px-3 py-3 border-b last:border-b-0 border-[color:var(--pb-sep)] active:bg-[color:var(--pb-fill)]"
              @click="router.push({ name: item.name })"
            >
              <span
                class="grid flex-none rounded-[10px] size-9 place-items-center"
                :class="item.tile || 'tile-violet'"
              >
                <span class="size-5" :class="item.icon" />
              </span>
              <span class="flex-1 text-left ios-body text-[color:var(--pb-ink)]">{{ item.label }}</span>
              <span class="flex-none size-[18px] text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
            </button>
          </li>
        </ul>
      </template>

      <button
        type="button"
        class="w-full mt-6 wt-btn text-[#C4383C] bg-[#C4383C]/10 active:bg-[#C4383C]/15"
        @click="confirmLogout = true"
      >
        退出登录
      </button>
      <div class="h-36" />
    </div>

    <AppSheet :open="confirmLogout" title="退出登录" @close="confirmLogout = false">
      <p class="text-sm text-[color:var(--pb-ink-2)]">
        退出后需要重新输入账号密码。已缓存的离线数据也会一并清除。
      </p>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn text-[#C4383C] bg-[#C4383C]/10 active:bg-[#C4383C]/15"
          @click="logout"
        >
          确认退出
        </button>
      </template>
    </AppSheet>
  </div>
</template>
