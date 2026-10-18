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
  <div class="crm-agent-workspace flex flex-col w-full h-full">
    <!-- 标题、能力说明、独立的按钮行都撤了：侧栏已经写着「AI 助手」，空页的引导语也说了能干什么。
         两张卡因此能和左侧边栏一样从头铺到尾，「新对话」挪进了历史对话卡的头部。 -->
    <div
      class="flex flex-1 min-h-0 gap-3 ps-0 pe-3 [.theme-classic_&]:gap-3 [.theme-classic_&]:ps-0 [.theme-classic_&]:pe-3"
    >
      <!-- 历史对话：开着好几个客户的活时能切回去 -->
      <div
        class="hidden w-56 min-h-0 flex-col border rounded-xl border-n-weak md:flex [.theme-classic_&]:w-60 [.theme-classic_&]:shrink-0 [.theme-classic_&]:rounded-2xl [.theme-classic_&]:border-[#e7e9ed] [.theme-classic_&]:bg-white [.theme-classic_&]:p-3"
      >
        <div
          class="flex items-center gap-2 px-2 pt-2 pb-4 shrink-0 text-heading-3 text-[#727987]"
        >
          <span
            aria-hidden="true"
            class="i-lucide-messages-square size-4 shrink-0"
          />
          <span class="flex-1 min-w-0">历史对话</span>
          <Button label="新对话" color="iris" size="sm" @click="newChat" />
        </div>
        <div class="flex flex-col min-h-0 overflow-y-auto">
          <!-- 只在还没有内容时摆「加载中」：这个列表每发一条消息就重拉一次，
               每次都闪一下会以为列表被清空了。 -->
          <div
            v-if="loading && !conversations.length"
            class="px-3 py-4 text-xs text-n-slate-11"
          >
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
            class="flex items-center gap-1 px-3 py-2 text-xs border-b border-n-weak/60 group [.theme-classic_&]:mb-1 [.theme-classic_&]:rounded-xl [.theme-classic_&]:border-0 [.theme-classic_&]:px-3 [.theme-classic_&]:py-3 [.theme-classic_&]:hover:bg-[#f3f4f6]"
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
      </div>

      <div
        class="flex-1 min-w-0 p-3 border rounded-xl border-n-weak [.theme-classic_&]:rounded-2xl [.theme-classic_&]:border-[#e7e9ed] [.theme-classic_&]:bg-white [.theme-classic_&]:p-5 [.theme-classic_&]:shadow-[0_6px_24px_-16px_rgba(30,40,60,0.16)]"
      >
        <CrmAgentPanel ref="panelRef" @conversation-changed="loadList" />
      </div>
    </div>
  </div>
</template>
