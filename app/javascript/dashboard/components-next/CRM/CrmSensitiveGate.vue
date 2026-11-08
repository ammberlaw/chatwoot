<script setup>
/* global axios */
// 敏感区解锁门：进员工档案/薪资配置/工资表这类页面前，重输一次登录密码，
// 过了之后 15 分钟内免验（后端 Crm::SensitiveSession，Redis 记时）。
//
// 做成组件而不是每页抄一遍：工资表那两页原来压根没有这道门，而后端
// payroll_sheets_controller 每个动作都挂着 ensure_sensitive_session——
// 结果是页面一打开就 403「需要二次验证」，还没有任何地方能输密码
// （2026-11-06 用户导 9 月工资表时撞上）。
//
// 解锁成功才渲染默认插槽，并 emit 一次 unlocked 让页面去拉数据：
// 没解锁就拉，拉回来的也只是 403。
import { ref, onMounted } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

const props = defineProps({
  // 这一屏为什么要验，照页面说法写（「员工薪资」「工资表」…）
  subject: { type: String, default: '本页数据' },
});
const emit = defineEmits(['unlocked']);

const { accountId } = useAccount();
const unlocked = ref(false);
const checking = ref(true);
const password = ref('');
const error = ref('');
const verifying = ref(false);

const url = () => `/api/v1/accounts/${accountId.value}/crm/sensitive_session`;

const pass = () => {
  unlocked.value = true;
  password.value = '';
  emit('unlocked');
};

const check = async () => {
  try {
    const { data } = await axios.get(url());
    if (data.active) pass();
  } catch {
    unlocked.value = false;
  } finally {
    checking.value = false;
  }
};

const unlock = async () => {
  if (!password.value || verifying.value) return;
  verifying.value = true;
  error.value = '';
  try {
    await axios.post(url(), { password: password.value });
    pass();
  } catch (e) {
    error.value =
      e.response?.status === 401 ? '密码不正确' : '验证失败，请重试';
  } finally {
    verifying.value = false;
  }
};

onMounted(check);

defineExpose({ unlocked });
</script>

<template>
  <slot v-if="unlocked" />
  <div
    v-else
    class="flex flex-col items-center justify-center gap-3 px-6 py-24 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
  >
    <span class="i-lucide-shield-check size-9 text-n-iris-9" />
    <p class="text-sm font-medium text-n-slate-12">
      {{ props.subject }}为高敏感信息
    </p>
    <p class="text-xs text-n-slate-11">
      请输入登录密码完成二次验证（15 分钟内免验）；所有查看与修改将留痕。
    </p>
    <div v-if="!checking" class="flex items-center gap-2 mt-1">
      <input
        v-model="password"
        type="password"
        class="h-9 px-3 text-sm border rounded-lg w-56 border-n-weak bg-n-solid-1 text-n-slate-12"
        placeholder="登录密码"
        @keyup.enter="unlock"
      />
      <button
        class="h-9 px-4 shrink-0 whitespace-nowrap disabled:opacity-50 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
        :disabled="!password || verifying"
        @click="unlock"
      >
        {{ verifying ? '验证中…' : '解锁' }}
      </button>
    </div>
    <span v-if="error" class="text-xs text-n-ruby-11">{{ error }}</span>
  </div>
</template>
