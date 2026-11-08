<script setup>
import { useI18n } from 'vue-i18n';
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
// 看板设置：目前只管「谁计入成交排行」。
// 名单只列 CRM 成员（crm=true，口径见 AccountUser#can_access_crm?）：车间、仓管、质检
// 这些岗位从不持有客户，摆进来只是让人在四十来个名字里找人更费劲。
// 为什么 CRM 成员里还要再勾一次：规则怎么写都有例外——副管兼跑业务要算、挂 manager 的
// 生产主管不算、建了号没人用的空号不算。与其堆条件，不如在这里勾。
// 勾选只影响「零成交的人要不要以 ¥0 留在榜上」；有订单的人数据来自真实单据，不受此开关影响。
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import MembersAPI from 'dashboard/api/crm/members';
import Input from 'dashboard/components-next/input/Input.vue';

const { t } = useI18n();
const members = ref([]);
const loading = ref(false);
const savingId = ref(null);
const keyword = ref('');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await MembersAPI.get({
      active: true,
      crm: true,
      per_page: 200,
    });
    members.value = data.payload || [];
  } catch {
    members.value = [];
    useAlert('成员列表加载失败');
  } finally {
    loading.value = false;
  }
};

const visible = computed(() => {
  const kw = keyword.value.trim().toLowerCase();
  if (!kw) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email || ''}`.toLowerCase().includes(kw)
  );
});

const pickedCount = computed(
  () => members.value.filter(m => m.in_sales_rank).length
);

const toggle = async (member, checked) => {
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { in_sales_rank: checked },
    });
    Object.assign(member, data);
  } catch {
    useAlert('保存失败');
    load();
  } finally {
    savingId.value = null;
  }
};

const roleLabel = m => {
  if (m.is_admin) return '管理员';
  return (
    {
      deputy_admin: '副管理员',
      manager: '部门负责人',
      sales: '业务员',
      hr: '人事',
    }[m.crm_role] || '成员'
  );
};

onMounted(load);
</script>

<template>
  <CrmSettingsLayout
    :title="t('CRM.SETTINGS_PAGE.DASHBOARD')"
    :description="t('CRM.SETTINGS_PAGE.DASHBOARD_NOTE')"
  >
    <template #toolbar>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <Input
          v-model="keyword"
          :placeholder="t('CRM.SETTINGS_PAGE.SEARCH_MEMBERS')"
          class="w-full sm:w-72"
        />
        <span class="text-label-small text-n-slate-11"
          >{{ t('CRM.SETTINGS_PAGE.PICKED', { count: pickedCount }) }} ·
          {{ t('CRM.SETTINGS_PAGE.AUTO_SAVE') }}</span
        >
      </div>
    </template>
    <p v-if="loading" class="py-12 text-center text-label text-n-slate-11">
      {{ t('CRM.SETTINGS_PAGE.LOADING') }}
    </p>
    <section
      v-else
      class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
    >
      <h2 class="mb-5 text-heading-2 text-n-slate-12">
        {{ t('CRM.SETTINGS_PAGE.RANK_MEMBERS') }}
      </h2>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <label
          v-for="m in visible"
          :key="m.id"
          class="flex min-h-14 min-w-0 cursor-pointer items-center gap-3 rounded-xl border px-4 py-3 transition-colors"
          :class="
            m.in_sales_rank
              ? 'border-n-slate-7 bg-n-alpha-2'
              : 'border-n-weak hover:bg-n-alpha-1'
          "
        >
          <input
            type="checkbox"
            class="size-4 shrink-0 accent-n-slate-12"
            :checked="m.in_sales_rank"
            :disabled="savingId === m.id"
            @change="toggle(m, $event.target.checked)"
          />
          <span class="min-w-0 flex-1 truncate text-label text-n-slate-12">{{
            m.name
          }}</span>
          <span class="shrink-0 text-label-small text-n-slate-11">{{
            roleLabel(m)
          }}</span>
        </label>
      </div>
      <p
        v-if="!visible.length"
        class="mb-0 py-8 text-center text-label-small text-n-slate-11"
      >
        {{ t('CRM.SETTINGS_PAGE.NO_MATCHES') }}
      </p>
    </section>
  </CrmSettingsLayout>
</template>
