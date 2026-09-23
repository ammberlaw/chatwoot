<script setup>
// 消息 tab 的占位页。团队沟通与客户会话都还没建，这里只说明要来什么，
// 不渲染任何假数据（工作台同一条规矩）。模块做好后把分段切换和列表填进来，
// 底部栏结构不用再动。
import PageHeader from '@/components/PageHeader.vue';
import EmptyState from '@/components/EmptyState.vue';

defineOptions({ name: 'MessagesPage' });

const PLANNED = [
  {
    icon: 'i-lucide-users-round',
    title: '团队沟通',
    desc: '同事之间的单聊与群组\n替代微信承载公司内部沟通',
  },
  {
    icon: 'i-lucide-message-circle',
    title: '客户会话',
    desc: 'WhatsApp 等渠道的客户消息，收发与历史记录',
  },
];
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="消息" />

    <div class="flex-1 min-h-0 px-4 overflow-y-auto">
      <EmptyState
        icon="i-ri-chat-3-fill"
        badge="i-ri-sparkling-fill"
        title="暂无新消息"
        :desc="['团队沟通与客户会话正在等待中', '上线后这里会收到所有找你的消息']"
      />

      <ul class="flex flex-col gap-2.5">
        <li v-for="p in PLANNED" :key="p.title">
          <div class="flex items-center gap-3 px-4 py-3.5 wt-glass">
            <span class="flex-none size-6 text-[color:var(--pb-ink)]" :class="p.icon" />
            <div class="flex-1 min-w-0">
              <div class="text-[15px] font-semibold leading-5 text-[color:var(--pb-ink)]">
                {{ p.title }}
              </div>
              <div class="mt-0.5 text-[12px] leading-4 whitespace-pre-line text-[color:var(--pb-ink-3)]">
                {{ p.desc }}
              </div>
            </div>
            <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
          </div>
        </li>
      </ul>

      <div class="h-36" />
    </div>
  </div>
</template>
