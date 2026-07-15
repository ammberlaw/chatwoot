<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import wootAPI from '../../../api/apiClient';

/* eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template */

const route = useRoute();
const router = useRouter();
const token = route.params.token;

const loading = ref(true);
const invite = ref(null);
const form = ref({ name: '', email: '', password: '' });
const submitting = ref(false);
const errorMessage = ref('');
const joinedEmail = ref('');

const inviteActive = computed(() => invite.value?.status === 'pending');
const statusHint = computed(() => {
  if (invite.value?.status === 'used') return '该邀请链接已被使用';
  if (invite.value?.status === 'expired') return '该邀请链接已过期';
  return '邀请链接无效';
});

// 与后端 Devise 密码策略一致：大写+小写+数字+特殊字符。
const passwordValid = computed(() => {
  const p = form.value.password;
  return (
    p.length >= 6 &&
    /[A-Z]/.test(p) &&
    /[a-z]/.test(p) &&
    /[0-9]/.test(p) &&
    /[!@#$%^&*()_+\-=[\]{}|']/.test(p)
  );
});
const canSubmit = computed(
  () =>
    form.value.name.trim() &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.value.email.trim()) &&
    passwordValid.value &&
    !submitting.value
);

onMounted(async () => {
  try {
    const { data } = await wootAPI.get(`public/api/v1/member_invites/${token}`);
    invite.value = data;
  } catch {
    invite.value = null;
  } finally {
    loading.value = false;
  }
});

const submit = async () => {
  if (!canSubmit.value) return;
  submitting.value = true;
  errorMessage.value = '';
  try {
    const { data } = await wootAPI.post(
      `public/api/v1/member_invites/${token}/accept`,
      {
        name: form.value.name.trim(),
        email: form.value.email.trim(),
        password: form.value.password,
      }
    );
    joinedEmail.value = data.email;
  } catch (e) {
    errorMessage.value = e?.response?.data?.error || '加入失败，请稍后重试';
  } finally {
    submitting.value = false;
  }
};

const goLogin = () => {
  router.push({ name: 'login', query: { email: joinedEmail.value } });
};
</script>

<template>
  <div
    class="flex flex-col items-center justify-center w-full min-h-screen px-4 py-12 bg-n-brand/5 dark:bg-n-background"
  >
    <div
      class="w-full max-w-md p-10 bg-white shadow-lg dark:bg-n-solid-2 rounded-2xl"
    >
      <p v-if="loading" class="text-sm text-center text-n-slate-10">加载中…</p>

      <!-- 无效/已用/已过期 -->
      <div
        v-else-if="!inviteActive && !joinedEmail"
        class="flex flex-col items-center gap-3 text-center"
      >
        <span
          class="grid rounded-full size-12 place-items-center bg-n-ruby-3 text-n-ruby-11"
        >
          <span class="i-lucide-link-2-off size-6" />
        </span>
        <h1 class="text-lg font-semibold text-n-slate-12">
          {{ statusHint }}
        </h1>
        <p class="text-sm text-n-slate-11">
          请联系超级管理员重新生成邀请链接。
        </p>
      </div>

      <!-- 加入成功 -->
      <div
        v-else-if="joinedEmail"
        class="flex flex-col items-center gap-3 text-center"
      >
        <span
          class="grid rounded-full size-12 place-items-center bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-check size-6" />
        </span>
        <h1 class="text-lg font-semibold text-n-slate-12">加入成功</h1>
        <p class="text-sm text-n-slate-11">
          你已加入
          {{ invite.account_name }}，用刚才设置的邮箱和密码登录即可开始使用。
        </p>
        <button
          type="button"
          class="w-full py-2.5 mt-2 text-sm font-medium text-white transition-colors rounded-xl bg-n-brand hover:brightness-110"
          @click="goLogin"
        >
          去登录
        </button>
      </div>

      <!-- 加入表单 -->
      <form v-else class="flex flex-col gap-4" @submit.prevent="submit">
        <div class="mb-1 text-center">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ invite.account_name }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">邀请你加入团队</p>
          <p v-if="invite.note" class="mt-1 text-xs text-n-slate-10">
            {{ invite.note }}
          </p>
        </div>

        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          姓名
          <input
            v-model="form.name"
            type="text"
            placeholder="你的姓名"
            class="px-3 py-2.5 text-sm border rounded-xl border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          邮箱
          <input
            v-model="form.email"
            type="email"
            placeholder="用于登录的邮箱"
            class="px-3 py-2.5 text-sm border rounded-xl border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          密码
          <input
            v-model="form.password"
            type="password"
            placeholder="设置登录密码"
            class="px-3 py-2.5 text-sm border rounded-xl border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
          <span
            class="text-xs"
            :class="
              form.password && !passwordValid
                ? 'text-n-ruby-11'
                : 'text-n-slate-10'
            "
          >
            至少 6 位，需包含大写、小写字母、数字和特殊字符
          </span>
        </label>

        <p v-if="errorMessage" class="text-sm text-n-ruby-11">
          {{ errorMessage }}
        </p>

        <button
          type="submit"
          :disabled="!canSubmit"
          class="w-full py-2.5 text-sm font-medium text-white transition-colors rounded-xl bg-n-brand hover:brightness-110 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {{ submitting ? '加入中…' : '加入团队' }}
        </button>
      </form>
    </div>
  </div>
</template>
