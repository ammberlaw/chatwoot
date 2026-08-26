<script setup>
/**
 * 文档中心「管理板块」面板：增删板块 + 设负责人(manager_ids) / 可见成员(viewer_ids)。
 * 后端 crm_doc_sections 一直支持；此面板仅管理员/副管理员可用。
 * 保存后 emit updated，父组件广播 crmDocSectionsUpdated 让侧栏板块即时刷新。
 */
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import DocSectionsAPI from 'dashboard/api/crm/docSections';
import CrmMemberAPI from 'dashboard/api/crm/members';
import OrgDepartmentsAPI from 'dashboard/api/org/departments';
import OrgMembershipsAPI from 'dashboard/api/org/memberships';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({ show: { type: Boolean, default: false } });
const emit = defineEmits(['close', 'updated']);

const members = ref([]);
const departments = ref([]);
const memberships = ref([]);
const sections = ref([]);
const newName = ref('');
const busy = ref(false);
// 展开中的成员选择器：`${sectionId}-manager_ids` / `-viewer_ids`
const openPicker = ref('');
// 当前展开选择器内的搜索词（同一时刻只开一个）
const pickerSearch = ref('');

const load = async () => {
  try {
    const [m, s, d, ms] = await Promise.all([
      CrmMemberAPI.get(),
      DocSectionsAPI.get(),
      OrgDepartmentsAPI.get(),
      OrgMembershipsAPI.get(),
    ]);
    members.value = m.data.payload || [];
    departments.value = d.data.payload || [];
    memberships.value = ms.data.payload || [];
    sections.value = (s.data.payload || []).map(x => ({
      id: x.id,
      name: x.name,
      manager_ids: [...(x.manager_ids || [])],
      viewer_ids: [...(x.viewer_ids || [])],
    }));
  } catch {
    useAlert('加载失败');
  }
};

watch(
  () => props.show,
  v => {
    if (v) {
      openPicker.value = '';
      pickerSearch.value = '';
      newName.value = '';
      load();
    }
  }
);

const memberName = id =>
  members.value.find(m => m.user_id === id)?.name || `#${id}`;

// 按组织架构把成员分组：每个部门一组，未归属任何部门的归「未分组」。
const groups = computed(() => {
  const byDept = new Map();
  departments.value.forEach(d =>
    byDept.set(d.id, { id: d.id, name: d.name, memberIds: [] })
  );
  const assigned = new Set();
  const known = new Set(members.value.map(m => m.user_id));
  memberships.value.forEach(ms => {
    const g = byDept.get(ms.department_id);
    if (!g || !known.has(ms.user_id)) return;
    if (!g.memberIds.includes(ms.user_id)) g.memberIds.push(ms.user_id);
    assigned.add(ms.user_id);
  });
  const list = [...byDept.values()].filter(g => g.memberIds.length);
  const ungrouped = members.value
    .map(m => m.user_id)
    .filter(id => !assigned.has(id));
  if (ungrouped.length)
    list.push({ id: 0, name: '未分组', memberIds: ungrouped });
  return list;
});

// 按搜索词过滤后的分组（隐藏空组）。
const visibleGroups = computed(() => {
  const q = pickerSearch.value.trim().toLowerCase();
  return groups.value
    .map(g => ({
      ...g,
      ids: q
        ? g.memberIds.filter(id => memberName(id).toLowerCase().includes(q))
        : g.memberIds,
    }))
    .filter(g => g.ids.length);
});

// 该组已勾选人数（部门行显示 n/total）。
const groupSelectedCount = (sec, field, ids) =>
  ids.filter(id => sec[field].includes(id)).length;

// 分组勾选态：none / some / all —— 决定部门行复选框图标（空/减号/勾）。
const groupState = (sec, field, ids) => {
  const selected = groupSelectedCount(sec, field, ids);
  if (!selected) return 'none';
  return selected === ids.length ? 'all' : 'some';
};

const saveField = async (sec, field) => {
  try {
    await DocSectionsAPI.updateSection(sec.id, {
      section: { [field]: sec[field] },
    });
    emit('updated');
  } catch {
    useAlert('保存失败');
    load();
  }
};

const addSection = async () => {
  const name = newName.value.trim();
  if (!name || busy.value) return;
  busy.value = true;
  try {
    await DocSectionsAPI.createSection({ section: { name } });
    newName.value = '';
    await load();
    emit('updated');
  } catch {
    useAlert('新增失败，可能板块名重复');
  } finally {
    busy.value = false;
  }
};

const removeSection = async sec => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `删除板块「${sec.name}」？板块内文件夹会变为未归属，不会删除文件。`
    )
  )
    return;
  try {
    await DocSectionsAPI.deleteSection(sec.id);
    await load();
    emit('updated');
  } catch {
    useAlert('删除失败');
  }
};

const toggleMember = (sec, field, userId) => {
  const arr = sec[field];
  const i = arr.indexOf(userId);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(userId);
  saveField(sec, field);
};

// 整组勾选/取消：已全选则移除该组，否则补齐该组。
const toggleGroup = (sec, field, ids) => {
  const arr = sec[field];
  if (ids.every(id => arr.includes(id))) {
    sec[field] = arr.filter(id => !ids.includes(id));
  } else {
    ids.forEach(id => {
      if (!arr.includes(id)) arr.push(id);
    });
  }
  saveField(sec, field);
};

const pickerKey = (sec, field) => `${sec.id}-${field}`;
const togglePicker = key => {
  openPicker.value = openPicker.value === key ? '' : key;
  pickerSearch.value = '';
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/40 p-4"
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-full max-w-2xl bg-n-solid-2 rounded-2xl shadow-xl max-h-[88vh] overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
        >
          <h2 class="text-base font-semibold text-n-slate-12">管理板块</h2>
          <button
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto p-5 flex flex-col gap-3">
          <!-- 新增板块 -->
          <div class="flex items-center gap-2">
            <Input
              v-model="newName"
              placeholder="新板块名称，如：售后资料"
              class="flex-1"
              @keyup.enter="addSection"
            />
            <Button
              label="添加板块"
              icon="i-lucide-plus"
              color="iris"
              size="sm"
              :disabled="busy || !newName.trim()"
              @click="addSection"
            />
          </div>

          <p
            v-if="!sections.length"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            还没有板块，上面添加一个。
          </p>

          <!-- 板块列表 -->
          <div
            v-for="sec in sections"
            :key="sec.id"
            class="p-3 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-center gap-2">
              <div class="flex-1 text-sm font-medium text-n-slate-12">
                {{ sec.name }}
              </div>
              <button
                class="p-1.5 rounded-lg text-n-ruby-11 hover:bg-n-alpha-1"
                title="删除板块"
                @click="removeSection(sec)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </div>

            <div class="grid grid-cols-2 gap-2 mt-2">
              <!-- 负责人 -->
              <div class="relative">
                <button
                  class="w-full flex items-center justify-between px-2.5 py-1.5 text-xs rounded-lg border border-n-weak hover:bg-n-alpha-1"
                  @click="togglePicker(pickerKey(sec, 'manager_ids'))"
                >
                  <span class="text-n-slate-11">
                    负责人：{{
                      sec.manager_ids.length
                        ? `${sec.manager_ids.length} 人`
                        : '未设'
                    }}
                  </span>
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-3.5 text-n-slate-10"
                  />
                </button>
                <div
                  v-if="openPicker === pickerKey(sec, 'manager_ids')"
                  class="absolute left-0 z-20 mt-1 w-64 rounded-lg bg-n-solid-1 border border-n-weak shadow-lg"
                >
                  <div class="p-1.5 border-b border-n-weak">
                    <input
                      v-model="pickerSearch"
                      placeholder="搜索成员…"
                      class="w-full px-2 py-1 text-xs rounded border border-n-weak bg-n-solid-2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
                    />
                  </div>
                  <div class="max-h-60 overflow-y-auto p-1">
                    <template v-for="g in visibleGroups" :key="g.id">
                      <button
                        class="w-full flex items-center gap-2 px-1.5 py-1 mt-0.5 rounded hover:bg-n-alpha-1"
                        @click="toggleGroup(sec, 'manager_ids', g.ids)"
                      >
                        <span
                          class="flex items-center justify-center size-3.5 rounded border shrink-0"
                          :class="
                            groupState(sec, 'manager_ids', g.ids) === 'none'
                              ? 'border-n-weak'
                              : 'bg-n-iris-9 border-n-iris-9'
                          "
                        >
                          <Icon
                            v-if="
                              groupState(sec, 'manager_ids', g.ids) === 'all'
                            "
                            icon="i-lucide-check"
                            class="size-3 text-white"
                          />
                          <Icon
                            v-else-if="
                              groupState(sec, 'manager_ids', g.ids) === 'some'
                            "
                            icon="i-lucide-minus"
                            class="size-3 text-white"
                          />
                        </span>
                        <span
                          class="flex-1 text-[11px] font-medium text-left text-n-slate-11"
                        >
                          {{ g.name }}
                        </span>
                        <span class="text-[10px] text-n-slate-10">
                          {{ groupSelectedCount(sec, 'manager_ids', g.ids) }}/{{
                            g.ids.length
                          }}
                        </span>
                      </button>
                      <label
                        v-for="id in g.ids"
                        :key="id"
                        class="flex items-center gap-2 pl-6 pr-2 py-1 text-xs rounded cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
                      >
                        <input
                          type="checkbox"
                          :checked="sec.manager_ids.includes(id)"
                          @change="toggleMember(sec, 'manager_ids', id)"
                        />
                        {{ memberName(id) }}
                      </label>
                    </template>
                    <p
                      v-if="!visibleGroups.length"
                      class="px-2 py-3 text-center text-[11px] text-n-slate-10"
                    >
                      无匹配成员
                    </p>
                  </div>
                </div>
                <div
                  v-if="sec.manager_ids.length"
                  class="mt-1 text-[11px] text-n-slate-10 truncate"
                >
                  {{ sec.manager_ids.map(memberName).join('、') }}
                </div>
              </div>

              <!-- 可见 -->
              <div class="relative">
                <button
                  class="w-full flex items-center justify-between px-2.5 py-1.5 text-xs rounded-lg border border-n-weak hover:bg-n-alpha-1"
                  @click="togglePicker(pickerKey(sec, 'viewer_ids'))"
                >
                  <span class="text-n-slate-11">
                    可见：{{
                      sec.viewer_ids.length
                        ? `${sec.viewer_ids.length} 人`
                        : '仅负责人/管理员'
                    }}
                  </span>
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-3.5 text-n-slate-10"
                  />
                </button>
                <div
                  v-if="openPicker === pickerKey(sec, 'viewer_ids')"
                  class="absolute right-0 z-20 mt-1 w-64 rounded-lg bg-n-solid-1 border border-n-weak shadow-lg"
                >
                  <div class="p-1.5 border-b border-n-weak">
                    <input
                      v-model="pickerSearch"
                      placeholder="搜索成员…"
                      class="w-full px-2 py-1 text-xs rounded border border-n-weak bg-n-solid-2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
                    />
                  </div>
                  <div class="max-h-60 overflow-y-auto p-1">
                    <template v-for="g in visibleGroups" :key="g.id">
                      <button
                        class="w-full flex items-center gap-2 px-1.5 py-1 mt-0.5 rounded hover:bg-n-alpha-1"
                        @click="toggleGroup(sec, 'viewer_ids', g.ids)"
                      >
                        <span
                          class="flex items-center justify-center size-3.5 rounded border shrink-0"
                          :class="
                            groupState(sec, 'viewer_ids', g.ids) === 'none'
                              ? 'border-n-weak'
                              : 'bg-n-iris-9 border-n-iris-9'
                          "
                        >
                          <Icon
                            v-if="
                              groupState(sec, 'viewer_ids', g.ids) === 'all'
                            "
                            icon="i-lucide-check"
                            class="size-3 text-white"
                          />
                          <Icon
                            v-else-if="
                              groupState(sec, 'viewer_ids', g.ids) === 'some'
                            "
                            icon="i-lucide-minus"
                            class="size-3 text-white"
                          />
                        </span>
                        <span
                          class="flex-1 text-[11px] font-medium text-left text-n-slate-11"
                        >
                          {{ g.name }}
                        </span>
                        <span class="text-[10px] text-n-slate-10">
                          {{ groupSelectedCount(sec, 'viewer_ids', g.ids) }}/{{
                            g.ids.length
                          }}
                        </span>
                      </button>
                      <label
                        v-for="id in g.ids"
                        :key="id"
                        class="flex items-center gap-2 pl-6 pr-2 py-1 text-xs rounded cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
                      >
                        <input
                          type="checkbox"
                          :checked="sec.viewer_ids.includes(id)"
                          @change="toggleMember(sec, 'viewer_ids', id)"
                        />
                        {{ memberName(id) }}
                      </label>
                    </template>
                    <p
                      v-if="!visibleGroups.length"
                      class="px-2 py-3 text-center text-[11px] text-n-slate-10"
                    >
                      无匹配成员
                    </p>
                  </div>
                </div>
                <div
                  v-if="sec.viewer_ids.length"
                  class="mt-1 text-[11px] text-n-slate-10 truncate"
                >
                  {{ sec.viewer_ids.map(memberName).join('、') }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-between px-5 py-3 border-t border-n-weak shrink-0"
        >
          <span class="text-xs text-n-slate-10">
            负责人可管理板块内容；可见留空＝仅负责人与管理员可见
          </span>
          <Button label="完成" color="iris" size="sm" @click="emit('close')" />
        </div>
      </div>
    </div>
  </Teleport>
</template>
