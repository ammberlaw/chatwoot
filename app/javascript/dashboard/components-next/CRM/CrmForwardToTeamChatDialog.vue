<script setup>
// 转发到团队沟通：从提成表/绩效表把摘要(含回跳链接、可选表图)转发给成员或群聊。
// 直接列出成员，勾选即可(无需已有沟通记录)——发送时对成员自动建/复用单聊；也可选已有群聊。
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ChatAPI from 'dashboard/api/chat/conversations';
import AgentAPI from 'dashboard/api/agents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const L = {
  title: '转发到团队沟通',
  search: '搜索成员 / 群聊…',
  groups: '群聊',
  members: '成员',
  empty: '暂无可选成员',
  message: '消息内容（可编辑）',
  send: '发送',
  pick: '请至少选择一个成员或群聊',
  sent: '已转发到团队沟通',
  error: '转发失败，请重试',
  withImage: '同时发送表图',
};

const currentUserId = useMapGetter('getCurrentUserID');

const dialogRef = ref(null);
const agents = ref([]);
const groups = ref([]);
const loading = ref(false);
const query = ref('');
const selected = ref(new Set()); // 目标键：'g:<convId>' 群聊 / 'm:<userId>' 成员
const message = ref('');
const sending = ref(false);
// 可选：调用方传入「生成表图 File」的异步函数；发送时若勾选则现场截图当附件一起发。
const imageFn = ref(null);
const includeImage = ref(false);

const match = txt =>
  (txt || '').toLowerCase().includes(query.value.trim().toLowerCase());
const filteredGroups = computed(() => groups.value.filter(g => match(g.name)));
const filteredMembers = computed(() =>
  agents.value.filter(a => match(a.name) || match(a.email))
);

const isSel = key => selected.value.has(key);
const toggle = key => {
  const s = new Set(selected.value);
  if (s.has(key)) s.delete(key);
  else s.add(key);
  selected.value = s;
};

const open = async (text, opts = {}) => {
  message.value = text || '';
  query.value = '';
  selected.value = new Set();
  agents.value = [];
  groups.value = [];
  imageFn.value = typeof opts.makeImage === 'function' ? opts.makeImage : null;
  includeImage.value = !!imageFn.value; // 有表图能力时默认勾选
  dialogRef.value?.open();
  loading.value = true;
  try {
    const [agentsRes, convRes] = await Promise.all([
      AgentAPI.get(),
      ChatAPI.list(),
    ]);
    // 排掉自己和已停用（离职）的账号——转发目标里不该再出现离职的人。
    agents.value = (agentsRes.data || []).filter(
      a => a.id !== currentUserId.value && !a.deactivated
    );
    groups.value = (convRes.data?.payload || []).filter(
      c => c.kind === 'group'
    );
  } catch {
    agents.value = [];
    groups.value = [];
  } finally {
    loading.value = false;
  }
};

// 成员 → 建/复用单聊拿到会话 id；群聊直接用其会话 id。
const resolveConversationId = async key => {
  if (key.startsWith('g:')) return Number(key.slice(2));
  const { data } = await ChatAPI.create({
    kind: 'direct',
    user_id: Number(key.slice(2)),
  });
  return data.id;
};

const send = async () => {
  if (!selected.value.size) {
    useAlert(L.pick);
    return;
  }
  if (!message.value.trim()) return;
  sending.value = true;
  try {
    let files = [];
    if (includeImage.value && imageFn.value) {
      const file = await imageFn.value(); // 只生成一次，多个目标复用
      if (file) files = [file];
    }
    const content = message.value.trim();
    // eslint-disable-next-line no-restricted-syntax
    for (const key of selected.value) {
      // eslint-disable-next-line no-await-in-loop
      const convId = await resolveConversationId(key);
      // eslint-disable-next-line no-await-in-loop
      await ChatAPI.send(convId, content, files);
    }
    useAlert(L.sent);
    dialogRef.value?.close();
  } catch {
    useAlert(L.error);
  } finally {
    sending.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog ref="dialogRef" :title="L.title" :show-confirm-button="false">
    <div class="flex flex-col gap-3">
      <Input v-model="query" :placeholder="L.search" class="reset-base" />

      <div
        class="flex flex-col gap-1 max-h-[40vh] overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1/60 p-1"
      >
        <div v-if="loading" class="p-6 text-sm text-center text-n-slate-10">
          …
        </div>
        <template v-else>
          <!-- 群聊 -->
          <template v-if="filteredGroups.length">
            <div
              class="sticky top-0 z-10 px-2 py-1 text-xs font-medium bg-n-solid-1 text-n-slate-10"
            >
              {{ L.groups }}
            </div>
            <button
              v-for="g in filteredGroups"
              :key="`g:${g.id}`"
              class="flex items-center gap-3 p-2 text-left rounded-lg transition-colors"
              :class="isSel(`g:${g.id}`) ? 'bg-n-iris-3' : 'hover:bg-n-alpha-1'"
              @click="toggle(`g:${g.id}`)"
            >
              <span
                class="grid rounded-full size-8 shrink-0 place-content-center bg-n-iris-4 text-n-iris-11"
              >
                <Icon icon="i-lucide-users" class="size-4" />
              </span>
              <span class="flex-1 text-sm truncate text-n-slate-12">
                {{ g.name }}
              </span>
              <Icon
                v-if="isSel(`g:${g.id}`)"
                icon="i-lucide-check"
                class="size-4 text-n-iris-11 shrink-0"
              />
            </button>
          </template>

          <!-- 成员 -->
          <div
            class="sticky top-0 z-10 px-2 py-1 text-xs font-medium bg-n-solid-1 text-n-slate-10"
          >
            {{ L.members }}
          </div>
          <div
            v-if="!filteredMembers.length"
            class="p-4 text-sm text-center text-n-slate-10"
          >
            {{ L.empty }}
          </div>
          <button
            v-for="a in filteredMembers"
            :key="`m:${a.id}`"
            class="flex items-center gap-3 p-2 text-left rounded-lg transition-colors"
            :class="isSel(`m:${a.id}`) ? 'bg-n-iris-3' : 'hover:bg-n-alpha-1'"
            @click="toggle(`m:${a.id}`)"
          >
            <Avatar
              :name="a.name || ''"
              :src="a.thumbnail || ''"
              :size="32"
              rounded-full
            />
            <div class="min-w-0 flex-1">
              <div class="text-sm truncate text-n-slate-12">{{ a.name }}</div>
              <div v-if="a.email" class="text-xs truncate text-n-slate-10">
                {{ a.email }}
              </div>
            </div>
            <Icon
              v-if="isSel(`m:${a.id}`)"
              icon="i-lucide-check"
              class="size-4 text-n-iris-11 shrink-0"
            />
          </button>
        </template>
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">{{ L.message }}</span>
        <TextArea v-model="message" :rows="5" class="reset-base" />
      </div>

      <div class="flex items-center justify-between">
        <label
          v-if="imageFn"
          class="flex items-center gap-2 text-sm cursor-pointer select-none text-n-slate-11"
        >
          <input
            v-model="includeImage"
            type="checkbox"
            class="accent-n-iris-9"
          />
          {{ L.withImage }}
        </label>
        <span v-else />
        <button
          class="h-9 px-4 disabled:opacity-50 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
          :disabled="sending || !selected.size"
          @click="send"
        >
          {{ selected.size ? `${L.send} (${selected.size})` : L.send }}
        </button>
      </div>
    </div>
  </Dialog>
</template>
