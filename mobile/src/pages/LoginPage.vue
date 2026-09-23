<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';

const router = useRouter();
const auth = useAuthStore();
const email = ref('');
const password = ref('');
const loading = ref(false);
const error = ref('');
const sessions = ref(null); // 非空 = 会话数已达上限，需先踢掉一个

const submit = async (revoke = {}) => {
  if (!email.value || !password.value) return;
  loading.value = true;
  error.value = '';
  try {
    await auth.login(email.value.trim(), password.value, revoke);
    router.replace({ name: 'home' });
  } catch (e) {
    const status = e.response?.status;
    if (status === 409 && e.response?.data?.sessions_limit_reached) {
      sessions.value = e.response.data.sessions || [];
    } else if (status === 401) {
      error.value = '邮箱或密码不正确';
    } else if (!e.response) {
      // 请求压根没到服务器：多半是没网或公司网络不通
      error.value = '连不上服务器，请检查网络后重试';
    } else {
      error.value = e.response?.data?.errors?.[0] || '登录失败，请稍后重试';
    }
  } finally {
    loading.value = false;
  }
};

const deviceLabel = s =>
  [s.device_name, s.platform_name, s.browser_name]
    .filter(v => v && v !== 'Unknown')
    .join(' · ') || '未知设备';

const timeLabel = s => {
  const t = s.last_activity_at || s.created_at;
  if (!t) return '';
  const d = new Date(t);
  return `${d.getMonth() + 1}月${d.getDate()}日 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};
</script>

<template>
  <div
    class="flex flex-col justify-center flex-1 min-h-0 px-6 pt-safeTop pb-safeBottom bg-gradient-to-br from-[#F7F7F7] to-[#EDEDEF]"
  >
    <div class="p-6 shadow-sm rounded-3xl bg-white/70 backdrop-blur-2xl">
      <h1 class="text-2xl font-bold text-center text-[color:var(--pb-ink)]">
        wintouchspace
      </h1>
      <p class="mt-1 mb-6 text-sm text-center text-[color:var(--pb-ink-2)]">
        登录你的工作账号
      </p>

      <input
        v-model="email"
        type="email"
        inputmode="email"
        autocomplete="username"
        placeholder="邮箱"
        class="w-full px-4 mb-3 text-base border rounded-xl h-12 border-[color:var(--pb-sep)] bg-[color:var(--pb-card)] text-[color:var(--pb-ink)] placeholder:text-[color:var(--pb-ink-3)]"
      />
      <input
        v-model="password"
        type="password"
        autocomplete="current-password"
        placeholder="密码"
        class="w-full px-4 mb-3 text-base border rounded-xl h-12 border-[color:var(--pb-sep)] bg-[color:var(--pb-card)] text-[color:var(--pb-ink)] placeholder:text-[color:var(--pb-ink-3)]"
        @keyup.enter="submit"
      />

      <p
        v-if="error"
        class="mb-3 text-xs text-center whitespace-pre-line text-[#C4383C]"
      >
        {{ error }}
      </p>

      <button
        type="button"
        class="w-full text-base font-semibold text-white h-12 rounded-xl bg-[color:var(--pb-ink)] active:bg-[color:var(--pb-ink)] disabled:opacity-60"
        :disabled="loading"
        @click="submit()"
      >
        {{ loading ? '登录中…' : '登录' }}
      </button>
    </div>

    <!-- 登录设备数达上限：选一个退出后再登录 -->
    <div
      v-if="sessions"
      class="p-5 mt-4 shadow-sm rounded-3xl bg-white/70 backdrop-blur-2xl"
    >
      <h2 class="text-base font-semibold text-[color:var(--pb-ink)]">登录设备已达上限</h2>
      <p class="mt-1 mb-3 text-sm text-[color:var(--pb-ink-2)]">
        选择一台退出登录，或全部退出后重新登录。
      </p>

      <!-- 相对定位 + 底部渐隐：列表被截断时给出「还能往下滚」的视觉提示 -->
      <div class="relative mb-4">
        <ul class="flex flex-col gap-2 overflow-y-auto max-h-64">
          <li v-for="s in sessions" :key="s.id">
            <button
              type="button"
              class="flex items-center justify-between w-full gap-3 p-3 text-left border rounded-xl border-[color:var(--pb-sep)] bg-[color:var(--pb-card)] active:bg-[color:var(--pb-fill)] disabled:opacity-60"
              :disabled="loading"
              @click="submit({ revoke_session_id: s.id })"
            >
              <span class="min-w-0">
                <span class="block text-sm font-medium truncate text-[color:var(--pb-ink)]">
                  {{ deviceLabel(s) }}
                </span>
                <span class="block text-xs truncate text-[color:var(--pb-ink-2)]">
                  {{ s.ip_address }} · {{ timeLabel(s) }}
                </span>
              </span>
              <span class="flex-none text-xs font-medium text-[color:var(--pb-accent)]">
                退出
              </span>
            </button>
          </li>
        </ul>
        <div
          class="absolute inset-x-0 bottom-0 h-8 pointer-events-none rounded-b-xl bg-gradient-to-t from-[color:var(--pb-card)] to-transparent"
        />
      </div>

      <button
        type="button"
        class="w-full text-sm font-medium rounded-xl h-11 text-[color:var(--pb-accent)] bg-[color:var(--pb-fill)] active:bg-[color:var(--pb-fill)] disabled:opacity-60"
        :disabled="loading"
        @click="submit({ revoke_all_sessions: true })"
      >
        全部退出并登录
      </button>
    </div>
  </div>
</template>
