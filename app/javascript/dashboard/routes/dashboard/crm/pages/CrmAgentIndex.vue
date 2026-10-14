<script setup>
// CRM AI 助手独立页：左边历史对话，右边当前对话。
// 客户详情里那个面板用的是同一个 CrmAgentPanel，只是带上客户上下文。
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAgentAPI from 'dashboard/api/crm/agent';
import CrmAgentPanel from 'dashboard/components-next/CRM/CrmAgentPanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const conversations = ref([]);
const panelRef = ref(null);
const loading = ref(false);

const loadList = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAgentAPI.get();
    conversations.value = data.payload || [];
  } catch (error) {
    useAlert(error?.response?.data?.error || '取对话列表失败');
  } finally {
    loading.value = false;
  }
};

const newChat = () => {
  panelRef.value?.reset();
  loadList();
};

const removeChat = async id => {
  try {
    await CrmAgentAPI.delete(id);
    conversations.value = conversations.value.filter(c => c.id !== id);
  } catch {
    useAlert('删除失败');
  }
};

onMounted(loadList);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <div class="flex items-baseline gap-2">
        <h1 class="text-xl font-semibold text-n-slate-12">AI 助手</h1>
        <span class="text-xs text-n-slate-11">
          查客户 · 翻往来邮件做总结 · 起草邮件和
          PI（都只出草稿，不会自动发出去）
        </span>
      </div>
      <Button label="新对话" color="iris" size="sm" @click="newChat" />
    </div>

    <div class="flex flex-1 min-h-0 gap-4 px-4 pb-4 sm:px-6 sm:pb-6">
      <!-- 历史对话：开着好几个客户的活时能切回去 -->
      <div
        class="hidden w-56 min-h-0 overflow-y-auto border rounded-xl border-n-weak md:block"
      >
        <div v-if="loading" class="px-3 py-4 text-xs text-n-slate-11">
          加载中…
        </div>
        <div
          v-else-if="!conversations.length"
          class="px-3 py-4 text-xs text-n-slate-11"
        >
          还没有对话。
        </div>
        <div
          v-for="c in conversations"
          :key="c.id"
          class="flex items-center gap-1 px-3 py-2 text-xs border-b border-n-weak/60 group"
        >
          <span class="flex-1 min-w-0 truncate text-n-slate-12">
            {{ c.title }}
          </span>
          <span v-if="c.crm_customer_name" class="shrink-0 text-n-slate-10">
            {{ c.crm_customer_name }}
          </span>
          <button
            type="button"
            title="删掉这个对话"
            class="hidden shrink-0 text-n-slate-10 hover:text-n-ruby-11 group-hover:block"
            @click="removeChat(c.id)"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
      </div>

      <div class="flex-1 min-w-0 p-3 border rounded-xl border-n-weak">
        <CrmAgentPanel ref="panelRef" />
      </div>
    </div>
  </div>
</template>
