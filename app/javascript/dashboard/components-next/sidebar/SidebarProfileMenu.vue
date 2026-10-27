<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import Auth from 'dashboard/api/auth';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import Avatar from 'next/avatar/Avatar.vue';
import SidebarProfileMenuStatus from './SidebarProfileMenuStatus.vue';
import MySignatureDialog from 'dashboard/components-next/CRM/MySignatureDialog.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  applyColorPalette,
  DEFAULT_COLOR_PALETTE,
  COLOR_PALETTES,
} from 'dashboard/helper/themeHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { useUISettings } from 'dashboard/composables/useUISettings';

const props = defineProps({
  isCollapsed: { type: Boolean, default: false },
  placement: { type: String, default: 'sidebar' },
});
const isTopbar = computed(() => props.placement === 'topbar');

const emit = defineEmits(['close', 'openKeyShortcutModal']);

const MAX_AVATAR_SIZE_MB = 15;

import {
  DropdownContainer,
  DropdownBody,
  DropdownSeparator,
  DropdownItem,
} from 'next/dropdown-menu/base';
import CustomBrandPolicyWrapper from '../../components/CustomBrandPolicyWrapper.vue';

defineOptions({
  inheritAttrs: false,
});

const { t } = useI18n();

const store = useStore();
const currentUser = useMapGetter('getCurrentUser');

// 自助更换头像：走原生 updateProfile，提交后 currentUser.avatar_url 响应式刷新。
const avatarInputRef = ref(null);
const openAvatarPicker = () => avatarInputRef.value?.click();
const onAvatarSelected = async event => {
  const file = event.target.files?.[0];
  event.target.value = ''; // 允许重选同一文件
  if (!file) return;
  if (!file.type.startsWith('image/')) {
    useAlert(t('SIDEBAR_ITEMS.AVATAR_INVALID_TYPE'));
    return;
  }
  if (!checkFileSizeLimit(file, MAX_AVATAR_SIZE_MB)) {
    useAlert(t('SIDEBAR_ITEMS.AVATAR_TOO_LARGE'));
    return;
  }
  try {
    await store.dispatch('updateProfile', {
      avatar: file,
      displayName: currentUser.value.display_name,
    });
    useAlert(t('SIDEBAR_ITEMS.AVATAR_UPDATED'));
  } catch {
    useAlert(t('SIDEBAR_ITEMS.AVATAR_UPDATE_FAILED'));
  }
};
// 我的签名（KPI 电子签）：存一次可复用，各签字环节一键盖章。
const signatureDialogRef = ref(null);
const openSignatureDialog = () => signatureDialogRef.value?.open();

// 配色主题：紫玻璃（默认）/ 蓝色商务。localStorage 即时生效不闪 + 镜像 ui_settings 跨设备恢复。
const { updateUISettings } = useUISettings();
const paletteMenuTitle = '配色主题';
const PALETTES = [
  {
    key: 'purple',
    label: '紫玻璃',
    swatch: 'bg-gradient-to-br from-[#5b5bd6] to-[#7c6cf0]',
  },
  {
    key: 'blue',
    label: '蓝色商务',
    swatch: 'bg-gradient-to-br from-[#2563eb] to-[#60a5fa]',
  },
  {
    key: 'classic',
    label: '经典灰',
    swatch: 'bg-gradient-to-br from-[#f4f4f5] to-[#373a40]',
  },
  {
    key: 'classicBlack',
    label: '雅黑',
    swatch: 'bg-gradient-to-r from-[#161616] to-[#f4f4f5]',
  },
  {
    key: 'obsidian',
    label: '曜石黑',
    swatch: 'bg-[#161616] ring-1 ring-inset ring-white/20',
  },
];
const savedPalette = LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_PALETTE);
const activePalette = ref(
  COLOR_PALETTES.includes(savedPalette) ? savedPalette : DEFAULT_COLOR_PALETTE
);
const selectPalette = key => {
  activePalette.value = key;
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_PALETTE, key);
  applyColorPalette(key);
  updateUISettings({ ui_palette: key });
};

const blackPalettes = [
  'purple',
  'blue',
  'classicBlack',
  'obsidian',
  'classic',
].map(key => PALETTES.find(palette => palette.key === key));
const accountId = useMapGetter('getCurrentAccountId');
const globalConfig = useMapGetter('globalConfig/get');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const showChatSupport = computed(() => {
  return (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONTACT_CHATWOOT_SUPPORT_TEAM
    ) && globalConfig.value.chatwootInboxToken
  );
});

const menuItems = computed(() => {
  return [
    {
      show: showChatSupport.value,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CONTACT_SUPPORT'),
      icon: 'i-lucide-life-buoy',
      click: () => {
        window.$chatwoot.toggle();
      },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS'),
      icon: 'i-lucide-keyboard',
      click: () => {
        emit('openKeyShortcutModal');
      },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.PROFILE_SETTINGS'),
      icon: 'i-lucide-user-pen',
      link: { name: 'profile_settings_index' },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.CHANGE_AVATAR'),
      icon: 'i-lucide-image-up',
      click: openAvatarPicker,
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.MY_SIGNATURE'),
      icon: 'i-lucide-signature',
      click: openSignatureDialog,
    },
    {
      show: currentUser.value.type === 'SuperAdmin',
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.SUPER_ADMIN_CONSOLE'),
      icon: 'i-lucide-castle',
      link: '/super_admin',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.USER_GUIDE_CRM'),
      icon: 'i-lucide-book-open',
      link: '/wintouch-crm-guide.html',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.USER_GUIDE_MES'),
      icon: 'i-lucide-book-open',
      link: '/wintouch-mes-guide.html',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.LOGOUT'),
      icon: 'i-lucide-power',
      click: Auth.logout,
    },
  ];
});

const allowedMenuItems = computed(() => {
  return menuItems.value.filter(item => item.show);
});
const topbarMenuGroups = computed(() => [
  ['i-lucide-life-buoy', 'i-lucide-keyboard', 'i-lucide-user-pen', 'i-lucide-image-up', 'i-lucide-signature'],
  ['i-lucide-castle'],
  ['i-lucide-book-open'],
  ['i-lucide-power'],
].map(icons => allowedMenuItems.value.filter(item => icons.includes(item.icon))).filter(group => group.length));
</script>

<template>
  <DropdownContainer
    class="relative min-w-0"
    :class="isTopbar ? 'w-auto [&>div.absolute]:right-0 [&>div.absolute]:top-full [&>div.absolute]:mt-2' : isCollapsed ? 'w-auto' : 'w-full'"
    @close="emit('close')"
  >
    <template #trigger="{ toggle, isOpen }">
      <slot name="trigger" :toggle="toggle" :is-open="isOpen">
      <button
        data-sidebar-profile-trigger
        class="flex gap-2 items-center p-1 text-left rounded-lg cursor-pointer hover:bg-n-alpha-1"
        :class="[
          { 'bg-n-alpha-1': isOpen },
          isCollapsed ? 'justify-center' : 'w-full',
        ]"
        :title="isCollapsed ? currentUser.available_name : undefined"
        @click="toggle"
      >
        <Avatar
          :size="32"
          :name="currentUser.available_name"
          :src="currentUser.avatar_url"
          class="flex-shrink-0"
        />
        <div v-if="!isCollapsed" class="min-w-0">
          <div class="text-sm font-medium leading-4 truncate text-n-slate-12">
            {{ currentUser.available_name }}
          </div>
          <div class="text-xs truncate text-n-slate-11">
            {{ currentUser.email }}
          </div>
        </div>
      </button>
      </slot>
    </template>
    <DropdownBody
      class="z-50 w-80"
      :class="[
        isTopbar ? '!top-0 !right-0 !bottom-auto !left-auto !m-0' : 'bottom-12 mb-2 ltr:left-0 rtl:right-0',
        isTopbar
          ? '!w-[304px] max-w-[calc(100vw-2rem)] [&>ul]:!bg-white [&>ul]:!border-[#e8ebe5] [&>ul]:!backdrop-blur-none [&>ul]:!rounded-[20px] [&>ul]:!p-0 [&>ul]:!gap-0 [&>ul]:!shadow-[0_16px_48px_-12px_rgba(0,0,0,0.24)]'
          : ['classicBlack', 'obsidian'].includes(activePalette)
          ? '[--slate-10:110_113_121] [--slate-11:79_82_89] [--slate-12:25_27_27] [--alpha-1:0,0,0,0.04] [--alpha-2:0,0,0,0.06] !w-[360px] max-w-[calc(100vw-2rem)] [&>ul]:!bg-white/80 [&>ul]:!border-white/80 [&>ul]:!backdrop-blur-2xl [&>ul]:!rounded-3xl [&>ul]:!p-0 [&>ul]:!gap-0 [&>ul]:!shadow-xl'
          : ''
      ]"
    >
      <div v-if="isTopbar" class="max-h-[calc(100dvh-6rem)] overflow-y-auto rounded-[20px] text-[#252a23]">
        <div class="flex items-center gap-3 px-4 py-3.5">
          <Avatar :size="34" :name="currentUser.available_name" :src="currentUser.avatar_url" rounded-full />
          <div class="min-w-0"><div class="truncate text-heading-3 font-semibold">{{ currentUser.available_name }}</div><div class="mt-0.5 truncate text-label-small text-[#8c9287]">{{ currentUser.email }}</div></div>
        </div>
        <div class="border-y border-[#eef0eb] px-3 py-3">
          <h3 class="m-0 mb-2 px-1 text-label-small font-medium text-[#8c9287]">{{ paletteMenuTitle }}</h3>
          <div class="grid grid-cols-5 gap-1">
            <button v-for="palette in blackPalettes" :key="palette.key" type="button" :title="palette.label" :aria-pressed="palette.key === activePalette" class="flex min-w-0 flex-col items-center gap-1.5 rounded-xl px-0.5 py-2 text-label-small transition-colors hover:bg-[#f5f6f2]" :class="palette.key === activePalette ? 'bg-[#f0f3e9] text-[#20241f]' : 'text-[#7f8778]'" @click="selectPalette(palette.key)">
              <span class="relative grid size-6 place-items-center rounded-full border border-black/5" :class="palette.swatch"><span v-if="palette.key === activePalette" class="i-lucide-check size-3 text-white drop-shadow" /></span>
              <span class="whitespace-nowrap">{{ palette.label }}</span>
            </button>
          </div>
        </div>
        <div class="px-2 pb-1">
          <div v-for="(group, index) in topbarMenuGroups" :key="group[0].icon" class="py-1" :class="index ? 'border-t border-[#eef0eb]' : ''">
            <CustomBrandPolicyWrapper v-for="item in group" :key="item.label" :show-on-custom-branded-instance="item.showOnCustomBrandedInstance">
              <DropdownItem v-bind="item" :icon="item.label === t('SIDEBAR_ITEMS.USER_GUIDE_MES') ? 'i-lucide-factory' : item.icon" class="!rounded-lg !px-3 !py-2 !text-label-small !text-[#444b3e] [&_.size-4]:!text-[#8b9384] hover:!bg-[#f4f6f0]" />
            </CustomBrandPolicyWrapper>
          </div>
        </div>
      </div>
      <div
        v-else-if="['classicBlack', 'obsidian'].includes(activePalette)"
        class="max-h-[calc(100dvh-6rem)] overflow-y-auto rounded-3xl"
      >
        <div
          class="flex items-center gap-3 rounded-t-3xl bg-[#161616]/95 px-5 py-4"
        >
          <Avatar
            :size="40"
            :name="currentUser.available_name"
            :src="currentUser.avatar_url"
            class="shrink-0"
          />
          <div class="min-w-0 flex-1">
            <p class="text-heading-3 font-semibold text-white truncate">
              {{ currentUser.available_name }}
            </p>
            <p class="mt-1 text-label-small text-white/60 truncate">
              {{ currentUser.email }}
            </p>
          </div>
        </div>
        <div class="p-4 border-b border-black/5">
          <h3 class="mb-3 text-heading-3 font-semibold text-[#191b1b]">
            {{ paletteMenuTitle }}
          </h3>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="palette in blackPalettes"
              :key="palette.key"
              type="button"
              class="flex items-center gap-2 rounded-xl border px-3 py-2.5 text-label-small transition-colors"
              :class="
                palette.key === activePalette
                  ? 'border-[#292b2b] bg-[#292b2b] font-semibold text-white'
                  : 'border-white/80 bg-white/50 text-[#3d4045] hover:bg-white/90'
              "
              @click="selectPalette(palette.key)"
            >
              <span
                class="size-4 shrink-0 rounded-full"
                :class="palette.swatch"
              />
              <span>{{ palette.label }}</span>
              <span
                v-if="palette.key === activePalette"
                class="i-lucide-check ml-auto size-4 text-[#ffc53d]"
              />
            </button>
          </div>
        </div>
        <div class="px-3 py-2">
          <template v-for="item in allowedMenuItems" :key="item.label">
            <CustomBrandPolicyWrapper
              :show-on-custom-branded-instance="
                item.showOnCustomBrandedInstance
              "
            >
              <DropdownItem
                v-bind="item"
                :icon="
                  item.label === t('SIDEBAR_ITEMS.USER_GUIDE_MES')
                    ? 'i-lucide-factory'
                    : item.icon
                "
                class="!rounded-xl !px-3 !py-2.5 !text-label-small hover:!bg-white/80"
              />
            </CustomBrandPolicyWrapper>
          </template>
        </div>
      </div>
      <template v-else>
        <SidebarProfileMenuStatus />
        <DropdownSeparator />
        <div class="px-2 py-2">
          <div class="px-2 pb-1.5 text-xs font-medium text-n-slate-11">
            {{ paletteMenuTitle }}
          </div>
          <div class="grid grid-cols-2 gap-2 px-2">
            <button
              v-for="p in PALETTES"
              :key="p.key"
              type="button"
              class="flex gap-2 items-center px-2.5 h-9 rounded-lg border transition-colors"
              :class="
                activePalette === p.key
                  ? 'border-n-iris-9 bg-n-alpha-1'
                  : 'border-n-weak hover:bg-n-alpha-1'
              "
              @click="selectPalette(p.key)"
            >
              <span
                class="flex-shrink-0 w-4 h-4 rounded-full shadow-sm"
                :class="p.swatch"
              />
              <span class="text-sm truncate text-n-slate-12">{{
                p.label
              }}</span>
              <span
                v-if="activePalette === p.key"
                class="flex-shrink-0 ml-auto size-4 i-lucide-check text-n-iris-9"
              />
            </button>
          </div>
        </div>
        <DropdownSeparator />
        <template v-for="item in allowedMenuItems" :key="item.label">
          <CustomBrandPolicyWrapper
            :show-on-custom-branded-instance="item.showOnCustomBrandedInstance"
          >
            <DropdownItem v-if="item.show" v-bind="item" />
          </CustomBrandPolicyWrapper>
        </template>
      </template>
    </DropdownBody>
  </DropdownContainer>
  <input
    ref="avatarInputRef"
    type="file"
    accept="image/*"
    class="hidden"
    @change="onAvatarSelected"
  />
  <MySignatureDialog ref="signatureDialogRef" />
</template>
