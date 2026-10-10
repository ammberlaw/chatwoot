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
} from 'dashboard/helper/themeHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { useUISettings } from 'dashboard/composables/useUISettings';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

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
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');

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
    key: 'beebot',
    label: '云白微光',
    swatch: 'bg-gradient-to-br from-[#f4f5f8] via-[#dfe0ff] to-[#7c7ef0]',
  },
  {
    key: 'classic',
    label: '经典灰',
    swatch: 'bg-gradient-to-br from-[#f4f4f5] to-[#373a40]',
  },
  {
    key: 'classicBlack',
    label: '经典灰·黑侧栏',
    swatch: 'bg-gradient-to-r from-[#161616] to-[#f4f4f5]',
  },
  {
    key: 'obsidian',
    label: '曜石黑',
    swatch: 'bg-[#161616] ring-1 ring-inset ring-white/20',
  },
  {
    key: 'inkarc',
    label: '墨黑圆弧',
    swatch: 'bg-gradient-to-br from-[#eff0f2] via-[#eff0f2] to-[#17181a]',
  },
];
const activePalette = ref(
  LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_PALETTE) || DEFAULT_COLOR_PALETTE
);
const selectPalette = key => {
  activePalette.value = key;
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_PALETTE, key);
  applyColorPalette(key);
  updateUISettings({ ui_palette: key });
};

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
</script>

<template>
  <DropdownContainer
    class="relative min-w-0"
    :class="isCollapsed ? 'w-auto' : 'w-full'"
    @close="emit('close')"
  >
    <template #trigger="{ toggle, isOpen }">
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
          :status="currentUserAvailability"
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
    </template>
    <DropdownBody class="bottom-12 z-50 mb-2 w-80 ltr:left-0 rtl:right-0">
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
            <span class="text-sm truncate text-n-slate-12">{{ p.label }}</span>
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
