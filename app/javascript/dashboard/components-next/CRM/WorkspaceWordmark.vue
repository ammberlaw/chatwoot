<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import wintouchLockup from 'dashboard/assets/images/wintouch/login-card-wordmark-rounded.png';

const filterId = `workspace-wordmark-${useId()}`;
const { t } = useI18n();
</script>

<template>
  <svg
    viewBox="0 0 2172 724"
    role="img"
    :aria-label="t('CRM.WORKSPACE_WALLPAPER.WORDMARK')"
  >
    <defs>
      <filter :id="filterId" x="0" y="0" width="100%" height="100%">
        <feFlood flood-color="currentColor" />
        <feComposite in2="SourceAlpha" operator="in" />
      </filter>
    </defs>
    <image
      :href="wintouchLockup"
      width="2172"
      height="724"
      :filter="`url(#${filterId})`"
    />
  </svg>
</template>
