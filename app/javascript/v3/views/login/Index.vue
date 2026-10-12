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
import loginGeometricWordmark from 'dashboard/assets/images/wintouch/login-wordmark-white-clean.png';
import loginCloudLogo from 'dashboard/assets/images/wintouch/login-header-logo.png';
import loginCardWordmark from 'dashboard/assets/images/wintouch/login-card-wordmark-rounded.png';

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
      loginCardWordmark,
      loginCloudLogo,
      loginGeometricWordmark,
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
    class="relative isolate flex flex-col w-full min-h-screen overflow-x-hidden bg-[#111111]"
  >
    <header class="flex items-center px-6 pt-7 sm:px-12">
      <img
        :src="loginCardWordmark"
        alt="Wintouch"
        class="h-auto w-[150px] brightness-0 invert"
      />
    </header>
    <div
      class="grid items-center flex-1 w-full max-w-[1280px] gap-10 px-6 mx-auto sm:px-12 lg:grid-cols-[1.35fr_1fr]"
    >
      <!-- Hero (branded artwork, copy intentionally not translated) -->
      <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
      <section class="hidden min-w-0 py-8 pl-6 lg:block xl:pl-12">
        <img
          :src="loginGeometricWordmark"
          alt="Wintouchspace"
          class="-mt-20 -mb-4 -ml-12 h-auto w-[calc(100%+96px)] max-w-none object-contain object-left xl:-ml-20 xl:w-[calc(100%+160px)]"
        />
        <div class="flex max-w-[590px] flex-col gap-2">
          <p
            class="whitespace-nowrap text-[48px] font-extrabold leading-[1.08] tracking-[-0.045em] text-white xl:text-[56px]"
          >
            bring a team
          </p>
          <div class="ml-20 flex items-center gap-5">
            <p
              class="text-[48px] font-extrabold leading-[1.08] tracking-[-0.045em] text-[#ffcc33] xl:text-[56px]"
            >
              together
            </p>
            <div
              class="relative top-1 flex h-[30px] w-[60px] shrink-0 items-center justify-end rounded-full bg-[#ffcc33] p-[3px]"
              aria-hidden="true"
            >
              <div
                class="size-6 rounded-full bg-white shadow-[0_3px_8px_rgba(0,0,0,0.15)]"
              />
            </div>
          </div>
        </div>
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
          class="flex flex-col rounded-[28px] border border-white/70 bg-white px-6 py-9 sm:px-10 sm:py-11 shadow-[0_24px_60px_-16px_rgba(0,0,0,0.12)] backdrop-blur-2xl backdrop-saturate-[1.4] [&_label]:sr-only [&_input]:!h-[50px] [&_input]:!rounded-2xl [&_input]:!bg-white [&_input]:!px-5 [&_input]:!text-[15px] [&_input]:![font-family:ui-rounded,'Avenir_Next','Arial_Rounded_MT_Bold','Trebuchet_MS',sans-serif] [&_input]:!font-medium [&_input]:!text-[#171717] [&_input]:!shadow-[0_2px_8px_rgba(0,0,0,0.04)] [&_input]:!outline-transparent [&_input:focus]:!outline-2 [&_input:focus]:!outline-[#e2b528] [&_input.error]:!outline-n-ruby-8 [&_input::placeholder]:!text-[#777777]"
          :class="{ 'animate-wiggle': loginApi.hasErrored }"
        >
          <div
            class="relative mb-7 h-[86px] w-[90px] self-center overflow-hidden"
            role="img"
            :aria-label="globalConfig.installationName"
          >
            <img
              :src="loginCloudLogo"
              alt=""
              class="absolute -left-[10px] -top-[26px] h-auto w-[360px] max-w-none"
            />
          </div>
          <div v-if="!email">
            <div class="flex flex-col gap-4">
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <div v-if="showSamlLogin" class="text-center">
                <router-link
                  to="/app/login/sso"
                  class="inline-flex items-center justify-center w-full px-4 py-3 bg-white rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.04)] hover:bg-n-alpha-2"
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
                class="-mt-2 self-end text-[13px] text-[#171717] hover:underline"
                tabindex="4"
              >
                {{ $t('LOGIN.FORGOT_PASSWORD') }}
              </router-link>
              <NextButton
                lg
                type="submit"
                data-testid="submit_button"
                class="w-full !h-[50px] !rounded-2xl !text-[17px] !font-semibold !bg-[#ffcc33] !text-[#171717] !shadow-none hover:!bg-[#f2bd27] transition-transform hover:!-translate-y-px motion-reduce:hover:!translate-y-0"
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
            class="lowercase text-link text-[#171717]"
          >
            {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
          </router-link>
        </p>
      </div>
    </div>

    <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
    <footer
      class="py-[22px] text-center text-[13px] tracking-[0.02em] text-white/60"
    >
      Designed &amp; Developed by
      <b class="font-semibold text-white">Amber Law</b>
      <div
        class="mt-1 flex flex-wrap items-center justify-center gap-x-4 gap-y-1 px-6 text-label-small text-[#999999]"
      >
        <span>
          © {{ new Date().getFullYear() }} 东莞市联迪科技有限公司 保留所有权利
        </span>
        <span>粤ICP备2026106012号-1</span>
      </div>
    </footer>
    <!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  </main>
</template>
