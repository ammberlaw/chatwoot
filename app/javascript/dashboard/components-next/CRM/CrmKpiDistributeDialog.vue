<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMemberAPI from 'dashboard/api/crm/members';
import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const dialogRef = ref(null);
const schemeId = ref(null);
const members = ref([]);
const selected = ref(new Set());
const loading = ref(false);
const busy = ref(false);

// 全员可下发（被考核对象不限 CRM 角色，运营等无角色成员也能选）；默认不勾选，由下发人自选。
const roleLabel = m => {
  if (m.crm_role === 'manager') return t('CRM.KPI_SHEETS.ROLE_MANAGER');
  if (m.crm_role === 'sales') return t('CRM.KPI_SHEETS.ROLE_SALES');
  return t('CRM.KPI_SHEETS.ROLE_MEMBER');
};

const open = async id => {
  schemeId.value = id;
  selected.value = new Set();
  loading.value = true;
  dialogRef.value?.open();
  try {
    // 只取在职成员：离职停用的人不该再出现在选人下拉里（后端按 deactivated_at 过滤）。
    const { data } = await CrmMemberAPI.get({ active: true });
    members.value = data.payload || [];
  } catch {
    members.value = [];
  } finally {
    loading.value = false;
  }
};

const toggle = uid => {
  const s = new Set(selected.value);
  if (s.has(uid)) {
    s.delete(uid);
  } else {
    s.add(uid);
  }
  selected.value = s;
};

// 按部门分组：40 来号人平铺着找人太费劲（2026-11-04 用户反馈）。
// 只认主部门，每人只出现一次——兼着几个部门的人要是每组都列一遍，比平铺还难找。
// departments 由后端按 is_primary 倒序给出，取第一个即主部门。
// 没挂部门的归到末尾「未分配部门」，不能让他们消失。
const groups = computed(() => {
  const map = new Map();
  members.value.forEach(m => {
    const key = m.departments?.[0] || '';
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(m);
  });
  const named = [...map.entries()]
    .filter(([k]) => k)
    .sort(([a], [b]) => a.localeCompare(b, 'zh'));
  const rest = map.get('') || [];
  return [
    ...named.map(([name, list]) => ({ name, list })),
    ...(rest.length
      ? [{ name: t('CRM.KPI_SHEETS.NO_DEPARTMENT'), list: rest }]
      : []),
  ];
});

// 整组勾选：一个部门十来号人，一个个点太慢。
const BOX_CLS = {
  all: 'bg-n-slate-12 border-n-slate-12',
  some: 'border-n-slate-12',
  none: 'border-n-weak',
};
const groupState = g => {
  const picked = g.list.filter(m => selected.value.has(m.user_id)).length;
  if (picked === 0) return 'none';
  return picked === g.list.length ? 'all' : 'some';
};
const toggleGroup = g => {
  const s = new Set(selected.value);
  const turnOn = groupState(g) !== 'all';
  g.list.forEach(m => (turnOn ? s.add(m.user_id) : s.delete(m.user_id)));
  selected.value = s;
};

const count = computed(() => selected.value.size);

const confirm = async () => {
  if (!count.value) return;
  busy.value = true;
  try {
    const { data } = await CrmKpiSchemeAPI.distribute(schemeId.value, [
      ...selected.value,
    ]);
    useAlert(
      t('CRM.KPI_SHEETS.DISTRIBUTE_DONE', {
        created: data.created,
        skipped: data.skipped,
      })
    );
    dialogRef.value?.close();
  } catch {
    useAlert(t('CRM.KPI_SHEETS.DISTRIBUTE_ERROR'));
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="t('CRM.KPI_SHEETS.DISTRIBUTE_TITLE')"
    :confirm-button-label="t('CRM.KPI_SHEETS.DISTRIBUTE_CONFIRM', { count })"
    :is-loading="busy"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-2">
      <p class="text-xs text-n-slate-11">
        {{ t('CRM.KPI_SHEETS.DISTRIBUTE_HINT') }}
      </p>
      <div v-if="loading" class="p-4 text-sm text-center text-n-slate-11">
        {{ t('CRM.KPI_SHEETS.LOADING') }}
      </div>
      <div
        v-else-if="!members.length"
        class="p-4 text-sm text-center text-n-slate-11"
      >
        {{ t('CRM.KPI_SHEETS.NO_SALES') }}
      </div>
      <div v-else class="flex flex-col gap-4 max-h-[55vh] overflow-y-auto">
        <div v-for="g in groups" :key="g.name" class="flex flex-col gap-1.5">
          <button
            type="button"
            class="flex items-center gap-2 px-1 text-left"
            @click="toggleGroup(g)"
          >
            <span
              class="size-4 shrink-0 rounded border flex items-center justify-center"
              :class="BOX_CLS[groupState(g)]"
            >
              <span
                v-if="groupState(g) === 'all'"
                class="i-lucide-check size-3 shrink-0 text-n-solid-1"
              />
              <span
                v-else-if="groupState(g) === 'some'"
                class="size-2 shrink-0 rounded-sm bg-n-slate-12"
              />
            </span>
            <span class="text-heading-3 text-n-slate-12">{{ g.name }}</span>
            <span class="text-label-small text-n-slate-10">{{
              g.list.length
            }}</span>
          </button>
          <label
            v-for="m in g.list"
            :key="m.user_id"
            class="flex items-center gap-3 px-3 py-2 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="selected.has(m.user_id)"
              @change="toggle(m.user_id)"
            />
            <span class="font-medium text-n-slate-12">{{ m.name }}</span>
            <span class="ml-auto text-xs text-n-slate-10">{{
              roleLabel(m)
            }}</span>
          </label>
        </div>
      </div>
    </div>
  </Dialog>
</template>
