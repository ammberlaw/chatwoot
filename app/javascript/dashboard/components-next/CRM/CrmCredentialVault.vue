<script setup>
/**
 * 文档中心「账号密码」：公司各类账号集中存放，按分组授权。
 *
 * 密码不随列表下发——「••••••」只是显示层，点开/复制才向后端要明文，每次都留一条查看记录。
 */
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';
import CredentialsAPI from 'dashboard/api/crm/credentials';
import CrmDocSectionManager from 'dashboard/components-next/CRM/CrmDocSectionManager.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// 经典灰把 iris 重定义成灰，主行动按钮在那儿会塌成灰；沿用全站约定换金黄。
const goColor = computed(() => (isClassicTheme() ? 'amber' : 'iris'));

// 两档（同知识库的公司文档/我的文档）：公司条目按分组授权、查看留痕；
// 个人条目创建人独占，不分组、不留痕。
const tab = ref('company');
const isPersonal = computed(() => tab.value === 'personal');

const groups = ref([]);
const entries = ref([]);
const personalEntries = ref([]);
const canManageGroups = ref(false);
const loading = ref(true);
const activeGroupId = ref(null);
const keyword = ref('');

// 已点开的条目 id → 明文密码。切换分组/重新加载时清空，避免明文停留在页面上。
const revealed = ref({});

const showGroupManager = ref(false);
const formRef = ref(null);
const logsRef = ref(null);
const logs = ref([]);
const saving = ref(false);
const editingId = ref(null);
const form = ref({
  groupId: null,
  name: '',
  url: '',
  username: '',
  password: '',
  note: '',
});

const groupOptions = computed(() =>
  groups.value.map(g => ({ value: g.id, label: g.name }))
);
const writableGroups = computed(() => groups.value.filter(g => g.can_edit));
const activeGroup = computed(() =>
  groups.value.find(g => g.id === activeGroupId.value)
);
// 「我的账号」人人可建；公司条目要有可维护的分组。
const canAdd = computed(
  () => isPersonal.value || writableGroups.value.length > 0
);

const visibleEntries = computed(() => {
  const q = keyword.value.trim().toLowerCase();
  const source = isPersonal.value ? personalEntries.value : entries.value;
  return source
    .filter(
      e =>
        isPersonal.value ||
        !activeGroupId.value ||
        e.group_id === activeGroupId.value
    )
    .filter(
      e =>
        !q ||
        `${e.name} ${e.username || ''} ${e.url || ''} ${e.note || ''}`
          .toLowerCase()
          .includes(q)
    );
});

const groupName = id => groups.value.find(g => g.id === id)?.name || '';
const canEditEntry = entry =>
  entry.personal === true ||
  groups.value.find(g => g.id === entry.group_id)?.can_edit === true;

const load = async () => {
  loading.value = true;
  revealed.value = {};
  try {
    const { data } = await CredentialsAPI.list();
    groups.value = data.groups || [];
    entries.value = data.credentials || [];
    personalEntries.value = data.personal || [];
    canManageGroups.value = data.can_manage_groups === true;
    if (
      activeGroupId.value &&
      !groups.value.some(g => g.id === activeGroupId.value)
    ) {
      activeGroupId.value = null;
    }
  } catch {
    useAlert('加载失败');
  } finally {
    loading.value = false;
  }
};

onMounted(load);

// 切换档位时把已展开的明文清掉，别让密码跨 tab 留在页面上。
const switchTab = key => {
  tab.value = key;
  revealed.value = {};
  activeGroupId.value = null;
  keyword.value = '';
};

const fetchPassword = async (entry, logAction) => {
  const { data } = await CredentialsAPI.reveal(entry.id, logAction);
  return data.password || '';
};

const toggleReveal = async entry => {
  if (revealed.value[entry.id] !== undefined) {
    delete revealed.value[entry.id];
    revealed.value = { ...revealed.value };
    return;
  }
  try {
    revealed.value = {
      ...revealed.value,
      [entry.id]: await fetchPassword(entry, 'reveal'),
    };
  } catch {
    useAlert('取密码失败');
  }
};

// 复制整条：名称 + 网址 + 账号 + 密码 + 备注，空字段不出现在结果里。
// 密码要明文，所以照样走 reveal——公司条目会记一条 copy 留痕，个人条目不记。
const copyAll = async entry => {
  try {
    const lines = [entry.name];
    if (entry.url) lines.push(`网址：${entry.url}`);
    if (entry.username) lines.push(`账号：${entry.username}`);
    if (entry.has_password) {
      lines.push(`密码：${await fetchPassword(entry, 'copy')}`);
    }
    if (entry.note) lines.push(`备注：${entry.note}`);
    await copyTextToClipboard(lines.join('\n'));
    useAlert('整条已复制');
  } catch {
    useAlert('复制失败');
  }
};

const copyPassword = async entry => {
  try {
    await copyTextToClipboard(await fetchPassword(entry, 'copy'));
    useAlert('密码已复制');
  } catch {
    useAlert('复制失败');
  }
};

const openCreate = () => {
  editingId.value = null;
  form.value = {
    groupId: isPersonal.value
      ? null
      : activeGroup.value?.can_edit
        ? activeGroupId.value
        : writableGroups.value[0]?.id || null,
    name: '',
    url: '',
    username: '',
    password: '',
    note: '',
  };
  formRef.value?.open();
};

const openEdit = entry => {
  editingId.value = entry.id;
  form.value = {
    groupId: entry.group_id,
    name: entry.name,
    url: entry.url || '',
    username: entry.username || '',
    password: '',
    note: entry.note || '',
  };
  formRef.value?.open();
};

const submit = async () => {
  if (!form.value.name.trim() || saving.value) return;
  if (!isPersonal.value && !form.value.groupId) return;
  saving.value = true;
  const payload = {
    scope: isPersonal.value ? 'personal' : 'company',
    group_id: isPersonal.value ? null : form.value.groupId,
    name: form.value.name.trim(),
    url: form.value.url.trim(),
    username: form.value.username.trim(),
    password: form.value.password,
    note: form.value.note,
  };
  try {
    if (editingId.value)
      await CredentialsAPI.updateEntry(editingId.value, payload);
    else await CredentialsAPI.createEntry(payload);
    formRef.value?.close();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    saving.value = false;
  }
};

const remove = async entry => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除「${entry.name}」？删除后无法恢复。`)) return;
  try {
    await CredentialsAPI.deleteEntry(entry.id);
    await load();
  } catch {
    useAlert('删除失败');
  }
};

const openLogs = async () => {
  logsRef.value?.open();
  try {
    const { data } = await CredentialsAPI.views();
    logs.value = data || [];
  } catch {
    useAlert('加载查看记录失败');
  }
};

const fmtTime = value =>
  new Date(value).toLocaleString('zh-CN', { hour12: false });

// 分组管理沿用文档中心「管理板块」面板（同一套 manager_ids/viewer_ids 语义）。
const groupManagerApi = {
  list: () => CredentialsAPI.list().then(r => r.data.groups || []),
  create: name => CredentialsAPI.createGroup({ name }),
  update: (id, fields) => CredentialsAPI.updateGroup(id, fields),
  remove: id => CredentialsAPI.deleteGroup(id),
};
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0">
    <!-- 档位 tab 与工具栏同一行：左边切档，右边搜索与操作 -->
    <div
      class="flex flex-wrap items-center gap-2 px-4 py-3 border-b sm:px-6 border-n-weak"
    >
      <button
        v-for="t in [
          { key: 'company', label: '公司账号' },
          { key: 'personal', label: '我的账号' },
        ]"
        :key="t.key"
        type="button"
        class="relative py-1 text-sm transition-colors"
        :class="
          tab === t.key
            ? 'font-semibold text-n-slate-12'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="switchTab(t.key)"
      >
        {{ t.label }}
        <span
          v-if="tab === t.key"
          class="absolute inset-x-0 -bottom-1 h-0.5 rounded-full bg-n-iris-9"
        />
      </button>

      <span v-if="!isPersonal" class="w-px h-4 mx-1 bg-n-weak" />

      <Button
        v-if="!isPersonal"
        label="全部"
        size="sm"
        :variant="activeGroupId === null ? 'solid' : 'faded'"
        :color="activeGroupId === null ? goColor : 'slate'"
        @click="activeGroupId = null"
      />
      <Button
        v-for="g in isPersonal ? [] : groups"
        :key="g.id"
        :label="g.name"
        size="sm"
        :variant="activeGroupId === g.id ? 'solid' : 'faded'"
        :color="activeGroupId === g.id ? goColor : 'slate'"
        @click="activeGroupId = g.id"
      />
      <Input
        v-model="keyword"
        placeholder="搜索名称 / 账号 / 网址"
        class="w-full ml-auto sm:w-56"
        custom-input-class="!h-8 !py-0"
      />
      <Button
        v-if="!isPersonal"
        label="查看记录"
        icon="i-lucide-history"
        variant="outline"
        color="slate"
        size="sm"
        @click="openLogs"
      />
      <Button
        v-if="canManageGroups && !isPersonal"
        label="管理分组"
        icon="i-lucide-shield-check"
        variant="outline"
        color="slate"
        size="sm"
        @click="showGroupManager = true"
      />
      <Button
        v-if="canAdd"
        :label="isPersonal ? '新建我的账号' : '新建账号'"
        icon="i-lucide-plus"
        :color="goColor"
        size="sm"
        @click="openCreate"
      />
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-base text-n-slate-11"
    >
      加载中…
    </div>

    <div
      v-else-if="!isPersonal && !groups.length"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-sm text-n-slate-11"
    >
      <Icon icon="i-lucide-lock" class="size-8 text-n-slate-9" />
      <p>你还没有被授权查看任何账号分组。</p>
      <p class="text-xs">让管理员在「管理分组」里把你加进可见成员。</p>
    </div>

    <div
      v-else-if="!visibleEntries.length"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{
        keyword.trim()
          ? '没有匹配的账号'
          : isPersonal
            ? '还没有你自己的账号，点右上角新建'
            : '这个分组还没有账号'
      }}
    </div>

    <div v-else class="flex-1 px-4 py-3 overflow-y-auto sm:px-6 sm:py-4">
      <!-- 手机卡片：7 列表格在手机上挤不下，同文档中心/销售订单的两套布局 -->
      <div class="flex flex-col gap-2 md:hidden">
        <div
          v-for="entry in visibleEntries"
          :key="`m-${entry.id}`"
          class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
        >
          <div class="flex items-center gap-2">
            <span class="font-medium truncate text-n-slate-12">
              {{ entry.name }}
            </span>
            <span
              v-if="!isPersonal"
              class="px-1.5 py-0.5 text-[11px] rounded-full shrink-0 bg-n-slate-3 text-n-slate-11"
            >
              {{ groupName(entry.group_id) }}
            </span>
            <span class="flex-1" />
            <button
              class="p-1 rounded shrink-0 text-n-slate-11 active:bg-n-alpha-1"
              title="复制整条"
              @click="copyAll(entry)"
            >
              <Icon icon="i-lucide-clipboard-list" class="size-4" />
            </button>
            <div v-if="canEditEntry(entry)" class="flex items-center gap-1">
              <button
                class="p-1 rounded text-n-slate-11 active:bg-n-alpha-1"
                title="编辑"
                @click="openEdit(entry)"
              >
                <Icon icon="i-lucide-pencil" class="size-4" />
              </button>
              <button
                class="p-1 rounded text-n-ruby-11 active:bg-n-alpha-1"
                title="删除"
                @click="remove(entry)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </div>
          </div>

          <div class="mt-2 flex flex-col gap-1.5 text-sm">
            <div v-if="entry.username" class="flex items-center gap-2">
              <span class="w-10 text-xs shrink-0 text-n-slate-10">账号</span>
              <span class="truncate text-n-slate-12">{{ entry.username }}</span>
            </div>
            <div v-if="entry.has_password" class="flex items-center gap-2">
              <span class="w-10 text-xs shrink-0 text-n-slate-10">密码</span>
              <span class="font-mono break-all text-n-slate-12">
                {{
                  revealed[entry.id] !== undefined
                    ? revealed[entry.id]
                    : '••••••••'
                }}
              </span>
              <button
                class="p-1 rounded shrink-0 text-n-slate-11 active:bg-n-alpha-1"
                :title="revealed[entry.id] !== undefined ? '隐藏' : '显示密码'"
                @click="toggleReveal(entry)"
              >
                <Icon
                  :icon="
                    revealed[entry.id] !== undefined
                      ? 'i-lucide-eye-off'
                      : 'i-lucide-eye'
                  "
                  class="size-4"
                />
              </button>
              <button
                class="p-1 rounded shrink-0 text-n-slate-11 active:bg-n-alpha-1"
                title="复制密码"
                @click="copyPassword(entry)"
              >
                <Icon icon="i-lucide-copy" class="size-4" />
              </button>
            </div>
            <a
              v-if="entry.url"
              :href="entry.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 text-xs"
            >
              <span class="w-10 shrink-0 text-n-slate-10">网址</span>
              <span class="truncate text-n-iris-11">{{ entry.url }}</span>
            </a>
            <div v-if="entry.note" class="flex gap-2 text-xs">
              <span class="w-10 shrink-0 text-n-slate-10">备注</span>
              <!-- min-w-0 + break-all：备注里常贴 vless:// 这种没有空格的长串，
                   只有 whitespace-pre-wrap 断不开（它只在词边界换行），整行会把
                   表格撑破、右侧被截掉（用户 2026-11-03 反馈）。flex 子项还要
                   min-w-0 才肯收缩，否则 break-all 也没地方断。 -->
              <span
                class="min-w-0 break-all whitespace-pre-wrap text-n-slate-11"
              >
                {{ entry.note }}
              </span>
            </div>
          </div>

          <div class="mt-2 text-[11px] text-n-slate-10">
            {{ fmtTime(entry.updated_at)
            }}{{ entry.updated_by ? ` · ${entry.updated_by}` : '' }}
          </div>
        </div>
      </div>

      <table class="hidden w-full text-sm md:table">
        <thead>
          <tr class="text-xs text-left text-n-slate-10">
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">名称</th>
            <th
              v-if="!isPersonal"
              class="pb-2 pr-4 font-medium whitespace-nowrap"
            >
              分组
            </th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">账号</th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">密码</th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">备注</th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">更新</th>
            <th class="pb-2 w-16" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="entry in visibleEntries"
            :key="entry.id"
            class="border-t border-n-weak"
          >
            <td class="py-2.5 pr-4 align-top">
              <div class="font-medium text-n-slate-12">{{ entry.name }}</div>
              <a
                v-if="entry.url"
                :href="entry.url"
                target="_blank"
                rel="noopener noreferrer"
                class="text-xs text-n-iris-11 hover:underline"
              >
                {{ entry.url }}
              </a>
            </td>
            <td
              v-if="!isPersonal"
              class="py-2.5 pr-4 align-top text-xs text-n-slate-11"
            >
              {{ groupName(entry.group_id) }}
            </td>
            <td class="py-2.5 pr-4 align-top text-n-slate-12">
              {{ entry.username || '—' }}
            </td>
            <td class="py-2.5 pr-4 align-top">
              <div v-if="entry.has_password" class="flex items-center gap-1.5">
                <span class="font-mono text-n-slate-12">
                  {{
                    revealed[entry.id] !== undefined
                      ? revealed[entry.id]
                      : '••••••••'
                  }}
                </span>
                <button
                  class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1"
                  :title="
                    revealed[entry.id] !== undefined ? '隐藏' : '显示密码'
                  "
                  @click="toggleReveal(entry)"
                >
                  <Icon
                    :icon="
                      revealed[entry.id] !== undefined
                        ? 'i-lucide-eye-off'
                        : 'i-lucide-eye'
                    "
                    class="size-4"
                  />
                </button>
                <button
                  class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1"
                  title="复制密码"
                  @click="copyPassword(entry)"
                >
                  <Icon icon="i-lucide-copy" class="size-4" />
                </button>
              </div>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <!-- break-all：备注里常贴 vless:// 这种没有空格的长串，只有
                 whitespace-pre-wrap 断不开（它只在词边界换行），max-w-xs 限了宽
                 就直接被右边界截掉，后半截看不见（用户 2026-11-03 反馈）。 -->
            <td
              class="py-2.5 pr-4 align-top text-xs break-all text-n-slate-11 max-w-xs whitespace-pre-wrap"
            >
              {{ entry.note || '—' }}
            </td>
            <td class="py-2.5 pr-4 align-top text-xs text-n-slate-10">
              <div>{{ fmtTime(entry.updated_at) }}</div>
              <div v-if="entry.updated_by">{{ entry.updated_by }}</div>
            </td>
            <td class="py-2.5 align-top">
              <div class="flex items-center gap-1">
                <button
                  class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1"
                  title="复制整条（名称/网址/账号/密码/备注）"
                  @click="copyAll(entry)"
                >
                  <Icon icon="i-lucide-clipboard-list" class="size-4" />
                </button>
                <template v-if="canEditEntry(entry)">
                  <button
                    class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1"
                    title="编辑"
                    @click="openEdit(entry)"
                  >
                    <Icon icon="i-lucide-pencil" class="size-4" />
                  </button>
                  <button
                    class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-1"
                    title="删除"
                    @click="remove(entry)"
                  >
                    <Icon icon="i-lucide-trash-2" class="size-4" />
                  </button>
                </template>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmDocSectionManager
      :show="showGroupManager"
      :api="groupManagerApi"
      title="管理账号分组"
      item-label="分组"
      add-placeholder="新分组名称"
      empty-text="还没有分组，上面添加一个。"
      delete-hint="分组内的账号会一并删除，无法恢复。"
      footer-hint="负责人可增删改本组账号；可见留空＝仅负责人与管理员可见"
      @close="showGroupManager = false"
      @updated="load"
    />

    <Dialog
      ref="formRef"
      :title="editingId ? '编辑账号' : '新建账号'"
      :confirm-button-label="editingId ? '保存' : '创建'"
      :confirm-button-color="goColor"
      :is-loading="saving"
      overflow-y-auto
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <label v-if="!isPersonal" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">分组</span>
          <SelectCard
            v-model="form.groupId"
            :options="
              groupOptions.filter(o =>
                writableGroups.some(g => g.id === o.value)
              )
            "
            trigger-class="w-full h-10"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">名称</span>
          <Input v-model="form.name" />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">网址</span>
          <Input v-model="form.url" placeholder="https://" />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">账号</span>
          <Input v-model="form.username" />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">密码</span>
          <Input
            v-model="form.password"
            :placeholder="editingId ? '留空＝不修改密码' : ''"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">备注</span>
          <TextArea
            v-model="form.note"
            :rows="3"
            placeholder="密保问题、绑定手机、续费日期等"
          />
        </label>
      </div>
    </Dialog>

    <Dialog
      ref="logsRef"
      title="密码查看记录"
      cancel-button-label="关闭"
      :show-confirm-button="false"
      overflow-y-auto
    >
      <p v-if="!logs.length" class="py-6 text-sm text-center text-n-slate-11">
        还没有查看记录。
      </p>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-xs text-left text-n-slate-10">
            <th class="pb-2 pr-4 font-medium">时间</th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">成员</th>
            <th class="pb-2 pr-4 font-medium whitespace-nowrap">账号</th>
            <th class="pb-2 font-medium whitespace-nowrap">动作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="log in logs" :key="log.id" class="border-t border-n-weak">
            <td class="py-2 pr-4 text-xs text-n-slate-11">
              {{ fmtTime(log.created_at) }}
            </td>
            <td class="py-2 pr-4 text-n-slate-12">{{ log.user_name }}</td>
            <td class="py-2 pr-4 text-n-slate-12">{{ log.credential_name }}</td>
            <td class="py-2 text-xs text-n-slate-11">
              {{ log.action === 'copy' ? '复制' : '查看' }}
            </td>
          </tr>
        </tbody>
      </table>
    </Dialog>
  </div>
</template>
