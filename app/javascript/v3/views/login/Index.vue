<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { SESSION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import wintouchLockup from 'dashboard/assets/images/wintouch/lockup.png';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import SessionLimitOverlay from 'dashboard/components/auth/SessionLimitOverlay.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    SessionLimitOverlay,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    return {
      wintouchLockup,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      sessionsLimitReached: false,
      limitedSessions: [],
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      // Use a method to get the translated text to avoid dynamic key warning
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      // wait for idle state
      this.requestIdleCallbackPolyfill(() => {
        // Remove the error query param from the url
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          // Check if sessions limit reached
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: { email: credentials.email },
            });
            return;
          }

          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      // MFA verification successful, continue with login
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
    retryLoginWithParams(extraParams) {
      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        ...extraParams,
      };

      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.loginApi.showLoading = true;
      login(credentials)
        .then(result => {
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }
          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    handleSessionRevoke(sessionId) {
      this.retryLoginWithParams({ revoke_session_id: sessionId });
    },
    handleSessionRevokeAll() {
      this.retryLoginWithParams({ revoke_all_sessions: true });
    },
    handleSessionLimitCancel() {
      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <main
    class="flex flex-col w-full min-h-screen overflow-x-hidden bg-gradient-to-br from-[#e9e9fb] via-[#eeecfc] to-[#f2ecfb]"
  >
    <header class="flex items-center px-6 pt-7 sm:px-12">
      <img :src="wintouchLockup" alt="Wintouch" class="w-auto h-8" />
    </header>

    <div
      class="grid items-center flex-1 w-full max-w-[1440px] gap-6 px-6 mx-auto sm:px-12 lg:grid-cols-[1.35fr_1fr]"
    >
      <!-- Hero (branded artwork, copy intentionally not translated) -->
      <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
      <section
        class="relative hidden py-10 pl-[72px] lg:block"
        aria-hidden="true"
      >
        <div
          class="absolute left-[640px] top-[52px] h-[90px] w-20 rounded-tr-[60px] border-t-[3px] border-r-[3px] border-dashed border-[#4a4a7a] opacity-75"
        />
        <div
          class="absolute left-[100px] top-[186px] h-[62px] w-20 rounded-bl-[60px] border-b-[3px] border-l-[3px] border-dashed border-[#4a4a7a] opacity-75 after:absolute after:-bottom-[11px] after:-right-3.5 after:text-[13px] after:text-[#6a5ae0] after:content-['▶']"
        />

        <div class="flex items-center my-1 gap-3.5">
          <span
            class="text-[58px] font-extrabold leading-[1.02] tracking-[-0.03em] text-[#232345]"
          >
            bring
          </span>
          <div
            class="grid size-[52px] shrink-0 place-content-center rounded-full bg-[#6a5ae0]"
          >
            <Icon icon="i-lucide-arrow-right" class="size-6 text-white" />
          </div>
          <div
            class="flex h-[52px] w-[140px] shrink-0 items-center justify-end rounded-full bg-gradient-to-r from-[#5b5bd6] to-[#8b5cf6] pr-2 shadow-[0_14px_30px_-12px_rgba(91,91,214,0.45)]"
          >
            <div
              class="size-[42px] rounded-full bg-[#f2f2f6] shadow-[0_4px_10px_rgba(0,0,0,0.15)]"
            />
          </div>
        </div>
        <div class="flex items-center my-1 gap-3.5">
          <div
            class="relative size-[58px] shrink-0 rounded-full bg-[#ffb224] after:absolute after:-right-[5px] after:top-[23px] after:size-2.5 after:rounded-full after:border-[3px] after:border-white after:bg-[#6a5ae0] after:content-['']"
          />
          <span
            class="text-[58px] font-extrabold leading-[1.02] tracking-[-0.03em] text-[#232345]"
          >
            a team
          </span>
        </div>
        <div class="flex items-center my-1 gap-3.5">
          <div
            class="relative h-[68px] w-[104px] shrink-0 before:absolute before:left-0 before:top-0 before:size-[68px] before:rounded-full before:bg-gradient-to-br before:from-[#7c5cf0] before:to-[#a06af0] before:content-[''] after:absolute after:right-0 after:top-0 after:size-[68px] after:rounded-full after:bg-[#c3bcf7] after:content-['']"
          />
          <span
            class="text-[58px] font-extrabold leading-[1.02] tracking-[-0.03em] text-[#232345]"
          >
            together
          </span>
        </div>

        <p class="mt-[26px] text-sm leading-[1.8] text-[#565673]">
          客户 · 商机 · 订单 · 邮件 · 绩效 —— 一个工作台，连接整个团队，
          <br />
          让协作贯穿外贸全流程。
        </p>
      </section>
      <!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->

      <!-- Right column -->
      <div class="w-full min-w-0 max-w-[380px] py-10 justify-self-center">
        <!-- Session Limit Section -->
        <SessionLimitOverlay
          v-if="sessionsLimitReached"
          :sessions="limitedSessions"
          @revoke="handleSessionRevoke"
          @revoke-all="handleSessionRevokeAll"
          @cancel="handleSessionLimitCancel"
        />

        <!-- MFA Verification Section -->
        <MfaVerification
          v-else-if="mfaRequired"
          :mfa-token="mfaToken"
          @verified="handleMfaVerified"
          @cancel="handleMfaCancel"
        />

        <!-- Regular Login Section -->
        <section
          v-else
          class="flex flex-col rounded-[28px] border border-white/70 bg-white/55 px-10 py-11 shadow-[0_24px_60px_-16px_rgba(80,80,160,0.25)] backdrop-blur-2xl backdrop-saturate-[1.4] [&_label]:sr-only [&_input]:!h-[50px] [&_input]:!rounded-2xl [&_input]:!bg-white [&_input]:!px-5 [&_input]:!text-[15px] [&_input]:!text-[#1c1c2e] [&_input]:!shadow-[0_2px_8px_rgba(80,80,160,0.08)] [&_input]:!outline-transparent [&_input:focus]:!outline-2 [&_input:focus]:!outline-[#6a5ae0] [&_input.error]:!outline-n-ruby-8 [&_input::placeholder]:!text-[#6f6f8c]"
          :class="{ 'animate-wiggle': loginApi.hasErrored }"
        >
          <img
            :src="wintouchLockup"
            alt="Wintouch"
            class="h-[38px] w-auto max-w-full self-center mb-7"
          />
          <div v-if="!email">
            <div class="flex flex-col gap-4">
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <div v-if="showSamlLogin" class="text-center">
                <router-link
                  to="/app/login/sso"
                  class="inline-flex items-center justify-center w-full px-4 py-3 bg-white rounded-2xl shadow-[0_2px_8px_rgba(80,80,160,0.08)] hover:bg-n-alpha-2"
                >
                  <Icon
                    icon="i-lucide-lock-keyhole"
                    class="size-5 text-n-slate-11"
                  />
                  <span class="ml-2 text-base font-medium text-n-slate-12">
                    {{ $t('LOGIN.SAML.LABEL') }}
                  </span>
                </router-link>
              </div>
              <SimpleDivider
                v-if="showGoogleOAuth || showSamlLogin"
                :label="$t('COMMON.OR')"
                class="uppercase"
              />
            </div>
            <form
              class="flex flex-col gap-[18px]"
              @submit.prevent="submitFormLogin"
            >
              <FormInput
                v-model="credentials.email"
                name="email_address"
                type="text"
                data-testid="email_input"
                :tabindex="1"
                required
                :label="$t('LOGIN.EMAIL.LABEL')"
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                :has-error="v$.credentials.email.$error"
                @input="v$.credentials.email.$touch"
              />
              <FormInput
                v-model="credentials.password"
                type="password"
                name="password"
                data-testid="password_input"
                required
                :tabindex="2"
                :label="$t('LOGIN.PASSWORD.LABEL')"
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                :has-error="v$.credentials.password.$error"
                @input="v$.credentials.password.$touch"
              />
              <router-link
                v-if="!globalConfig.disableUserProfileUpdate"
                to="auth/reset/password"
                class="-mt-2 self-end text-[13px] text-[#6a5ae0] hover:underline"
                tabindex="4"
              >
                {{ $t('LOGIN.FORGOT_PASSWORD') }}
              </router-link>
              <NextButton
                lg
                type="submit"
                data-testid="submit_button"
                class="w-full !h-[50px] !rounded-2xl !text-[17px] !font-semibold !bg-gradient-to-r !from-[#6a5ae0] !to-[#8b5cf6] !shadow-[0_14px_30px_-10px_rgba(106,90,224,0.5)] transition-transform hover:!-translate-y-px motion-reduce:hover:!translate-y-0"
                :tabindex="3"
                :label="$t('LOGIN.SUBMIT')"
                :disabled="loginApi.showLoading"
                :is-loading="loginApi.showLoading"
              />
            </form>
          </div>
          <div v-else class="flex items-center justify-center">
            <Spinner color-scheme="primary" size="" />
          </div>
        </section>

        <p
          v-if="showSignupLink"
          class="mt-4 text-sm text-center text-n-slate-11"
        >
          {{ $t('COMMON.OR') }}
          <router-link
            to="auth/signup"
            class="lowercase text-link text-[#6a5ae0]"
          >
            {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
          </router-link>
        </p>
      </div>
    </div>

    <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
    <footer
      class="py-[22px] text-center text-[13px] tracking-[0.02em] text-[#6d6d88]"
    >
      Designed &amp; Developed by
      <b class="font-semibold text-[#6a5ae0]">Amber Law</b>
    </footer>
    <!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  </main>
</template>
