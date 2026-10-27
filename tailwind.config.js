const { slateDark } = require('@radix-ui/colors');
import { colors } from './theme/colors';
import { icons } from './theme/icons';
const defaultTheme = require('tailwindcss/defaultTheme');
const {
  iconsPlugin,
  getIconCollections,
} = require('@egoist/tailwindcss-icons');

const defaultSansFonts = [
  '-apple-system',
  'system-ui',
  'BlinkMacSystemFont',
  '"Segoe UI"',
  'Roboto',
  '"Helvetica Neue"',
  'Tahoma',
  'Arial',
  'sans-serif !important',
];

const tailwindConfig = {
  darkMode: 'class',
  content: [
    './enterprise/app/views/**/*.erb',
    './app/javascript/widget/**/*.vue',
    './app/javascript/v3/**/*.vue',
    './app/javascript/dashboard/**/*.vue',
    './app/javascript/portal/**/*.vue',
    './app/javascript/shared/**/*.vue',
    './app/javascript/survey/**/*.vue',
    './app/javascript/dashboard/components-next/**/*.vue',
    './app/javascript/dashboard/helper/**/*.js',
    './app/javascript/dashboard/composables/**/*.js',
    './app/javascript/dashboard/components-next/**/*.js',
    './app/javascript/dashboard/routes/dashboard/**/**/*.js',
    './app/views/**/*.erb',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: defaultSansFonts,
        inter: ['Inter', ...defaultSansFonts],
        interDisplay: ['InterDisplay', ...defaultSansFonts],
      },
      fontWeight: {
        420: '420',
        440: '440',
        460: '460',
        520: '520',
        620: '620',
      },
      typography: {
        bubble: {
          css: {
            color: 'rgb(var(--slate-12))',
            lineHeight: '1.6',
            fontSize: '14px',
            '*': {
              '&:first-child': {
                marginTop: '0',
              },
            },
            overflowWrap: 'anywhere',

            strong: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
            },

            b: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
            },

            h1: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1.25rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            h2: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            h3: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            hr: {
              marginTop: '1.5em',
              marginBottom: '1.5em',
            },
            a: {
              color: 'rgb(var(--slate-12))',
              textDecoration: 'underline',
            },
            ul: {
              paddingInlineStart: '0',
              listStylePosition: 'inside',
            },
            ol: {
              paddingInlineStart: '0',
              listStylePosition: 'inside',
            },
            'ul > li': {
              marginBlockEnd: '0.5em',
              listStyleType: 'disc',
              paddingInlineStart: '1.5em',
              textIndent: '-1.5em',
            },
            'ol > li': {
              marginBlockEnd: '0.5em',
              listStyleType: 'decimal',
              paddingInlineStart: '1.5em',
              textIndent: '-1.5em',
            },
            'li > p:first-child': {
              display: 'inline',
            },
            'li > *': {
              textIndent: '0',
            },
            blockquote: {
              color: 'rgb(var(--slate-11))',
              borderLeft: `4px solid rgb(var(--black-alpha-1))`,
              paddingLeft: '1em',
              '[dir="rtl"] &': {
                borderLeft: 'none',
                paddingLeft: '0',
                borderRight: `4px solid rgb(var(--black-alpha-1))`,
                paddingRight: '1em',
              },
              '[dir="ltr"] &': {
                borderRight: 'none',
                paddingRight: '0',
              },
            },
            code: {
              backgroundColor: 'rgb(var(--alpha-3))',
              color: 'rgb(var(--slate-11))',
              padding: '0.2em 0.4em',
              borderRadius: '4px',
              fontSize: '0.95em',
              '&::before': {
                content: `none`,
              },
              '&::after': {
                content: `none`,
              },
            },
            pre: {
              backgroundColor: 'rgb(var(--alpha-3))',
              padding: '1em',
              borderRadius: '6px',
              overflowX: 'auto',
            },
            table: {
              width: '100%',
              borderCollapse: 'collapse',
            },
            th: {
              padding: '0.75em',
              color: 'rgb(var(--slate-12))',
              border: `none`,
              textAlign: 'start',
              fontWeight: '600',
            },
            tr: {
              border: `none`,
            },
            td: {
              padding: '0.75em',
              border: `none`,
            },
            img: {
              maxWidth: '100%',
              height: 'auto',
              marginTop: 'unset',
              marginBottom: 'unset',
            },
          },
        },
      },
    },
    screens: {
      xs: '480px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
      '3xl': '1900px',
    },
    fontSize: {
      ...defaultTheme.fontSize,
      xxs: '0.625rem',
    },
    colors: {
      transparent: 'transparent',
      white: '#fff',
      'modal-backdrop-light': 'rgba(0, 0, 0, 0.4)',
      'modal-backdrop-dark': 'rgba(0, 0, 0, 0.6)',
      current: 'currentColor',
      ...colors,
      body: slateDark.slate7,
    },
    keyframes: {
      'ai-face-happy': {
        '0%': { opacity: '1' },
        '24%': { opacity: '1' },
        '24.9999%': { opacity: '0' },
        '100%': { opacity: '0' },
      },
      'ai-face-curious': {
        '0%': { opacity: '0' },
        '24.99%': { opacity: '0' },
        '25%': { opacity: '1' },
        '49%': { opacity: '1' },
        '49.9999%': { opacity: '0' },
        '100%': { opacity: '0' },
      },
      'ai-face-surprise': {
        '0%': { opacity: '0' },
        '49.99%': { opacity: '0' },
        '50%': { opacity: '1' },
        '74%': { opacity: '1' },
        '74.9999%': { opacity: '0' },
        '100%': { opacity: '0' },
      },
      'ai-face-goofy': {
        '0%': { opacity: '0' },
        '74.99%': { opacity: '0' },
        '75%': { opacity: '1' },
        '99%': { opacity: '1' },
        '99.9999%': { opacity: '0' },
        '100%': { opacity: '0' },
      },
      'ai-cloud-idle': {
        '0%, 100%': { transform: 'translateY(0) rotate(-3deg) scale(1)' },
        '30%': { transform: 'translateY(-6px) rotate(3deg) scale(1.03, 0.98)' },
        '60%': { transform: 'translateY(-2px) rotate(-2deg) scale(0.98, 1.03)' },
        '80%': { transform: 'translateY(-5px) rotate(1deg) scale(1)' },
      },
      ...defaultTheme.keyframes,
      "wsh-travel": {"0%, 15%, 100%": {"transform": "translateX(-8px)"}, "45%, 72%": {"transform": "translateX(8px)"}},
      "wsh-route": {"0%, 15%, 100%": {"transform": "translateX(0)"}, "45%, 72%": {"transform": "translateX(130px)"}},
      "wsh-unfold": {"0%, 100%": {"transform": "translateY(7px) rotate(-1deg)"}, "35%, 70%": {"transform": "translateY(0) rotate(0deg)"}},
      "wsh-file": {"0%, 100%": {"transform": "translateY(10px)"}, "35%, 70%": {"transform": "translateY(-5px)"}},
      "wsh-folder": {"0%, 100%": {"transform": "rotateX(0deg)"}, "35%, 70%": {"transform": "rotateX(-25deg)"}},
      // Workspace illustrations: transform / opacity only.
      "wsh-front": {"0%, 15%, 100%": {"transform": "translate(0, 0) rotate(-5deg)"}, "38%, 68%": {"transform": "translate(7px, 10px) rotate(3deg)"}},
      "wsh-middle": {"0%, 15%, 100%": {"transform": "translate(0, 0) rotate(1deg)"}, "38%, 68%": {"transform": "translate(-8px, -7px) rotate(-4deg)"}},
      "wsh-back": {"0%, 15%, 100%": {"transform": "translate(0, 0) rotate(6deg)"}, "38%, 68%": {"transform": "translate(7px, -15px) rotate(6deg)"}},
      "wsh-order": {"0%, 12%": {"transform": "translateX(0)", "opacity": "1"}, "40%, 52%": {"transform": "translateX(80px)", "opacity": "1"}, "75%, 86%": {"transform": "translateX(160px)", "opacity": "1"}, "94%": {"transform": "translateX(160px)", "opacity": "0"}, "95%": {"transform": "translateX(0)", "opacity": "0"}, "100%": {"transform": "translateX(0)", "opacity": "1"}},
      "wsh-ledger": {"0%, 100%": {"transform": "translateY(3px) rotate(-3deg)"}, "50%": {"transform": "translateY(-4px) rotate(2deg)"}},
      "wsh-check-one": {"0%, 12%, 100%": {"opacity": "0"}, "22%, 86%": {"opacity": "1"}},
      "wsh-check-two": {"0%, 32%, 100%": {"opacity": "0"}, "42%, 86%": {"opacity": "1"}},
      "wsh-check-three": {"0%, 52%, 100%": {"opacity": "0"}, "62%, 86%": {"opacity": "1"}},
      "wsh-message-one": {"0%, 8%, 100%": {"opacity": ".2", "transform": "translateY(8px)"}, "20%, 85%": {"opacity": "1", "transform": "translateY(0)"}},
      "wsh-message-two": {"0%, 30%, 100%": {"opacity": ".2", "transform": "translateY(8px)"}, "42%, 85%": {"opacity": "1", "transform": "translateY(0)"}},
      // 看板告警条的纵向轮播：内容复制一份首尾相接，走完一整份正好无缝衔接。
      // 要求每行等高且列表无 gap，否则 -50% 落点会差半个间距、循环处会跳一下。
      'marquee-y': {
        '0%': { transform: 'translateY(0)' },
        '100%': { transform: 'translateY(-50%)' },
      },
      wiggle: {
        '0%': { transform: 'translateX(0)' },
        '15%': { transform: 'translateX(0.375rem)' },
        '30%': { transform: 'translateX(-0.375rem)' },
        '45%': { transform: 'translateX(0.375rem)' },
        '60%': { transform: 'translateX(-0.375rem)' },
        '75%': { transform: 'translateX(0.375rem)' },
        '90%': { transform: 'translateX(-0.375rem)' },
        '100%': { transform: 'translateX(0)' },
      },
      'fade-in-up': {
        '0%': { opacity: 0, transform: 'translateY(0.5rem)' },
        '100%': { opacity: 1, transform: 'translateY(0)' },
      },
      'loader-pulse': {
        '0%': { opacity: 0.4 },
        '50%': { opacity: 1 },
        '100%': { opacity: 0.4 },
      },
      'card-select': {
        '0%, 100%': {
          transform: 'translateX(0)',
        },
        '50%': {
          transform: 'translateX(1px)',
        },
      },
      shake: {
        '0%, 100%': { transform: 'translateX(0)' },
        '25%': { transform: 'translateX(0.234375rem)' },
        '50%': { transform: 'translateX(-0.234375rem)' },
        '75%': { transform: 'translateX(0.234375rem)' },
      },
    },
    animation: {
      'ai-face-happy': 'ai-face-happy 10s steps(1, end) infinite',
      'ai-face-curious': 'ai-face-curious 10s steps(1, end) infinite',
      'ai-face-surprise': 'ai-face-surprise 10s steps(1, end) infinite',
      'ai-face-goofy': 'ai-face-goofy 10s steps(1, end) infinite',
      'ai-cloud-idle': 'ai-cloud-idle 4.8s ease-in-out infinite',
      ...defaultTheme.animation,
      "wsh-travel": "wsh-travel 8s cubic-bezier(0.45, 0, 0.25, 1) -1s infinite",
      "wsh-route": "wsh-route 8s cubic-bezier(0.45, 0, 0.25, 1) -1s infinite",
      "wsh-unfold": "wsh-unfold 8s cubic-bezier(0.45, 0, 0.25, 1) -2s infinite",
      "wsh-file": "wsh-file 8s cubic-bezier(0.45, 0, 0.25, 1) -1s infinite",
      "wsh-folder": "wsh-folder 8s cubic-bezier(0.45, 0, 0.25, 1) -1s infinite",
      "wsh-front": "wsh-front 7s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      "wsh-middle": "wsh-middle 7s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      "wsh-back": "wsh-back 7s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      "wsh-order": "wsh-order 7s cubic-bezier(0.45, 0, 0.25, 1) -0.6s infinite",
      "wsh-ledger": "wsh-ledger 7s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      "wsh-check-one": "wsh-check-one 7s cubic-bezier(0.45, 0, 0.25, 1) -1.4s infinite",
      "wsh-check-two": "wsh-check-two 7s cubic-bezier(0.45, 0, 0.25, 1) -1.4s infinite",
      "wsh-check-three": "wsh-check-three 7s cubic-bezier(0.45, 0, 0.25, 1) -1.4s infinite",
      "wsh-message-one": "wsh-message-one 8s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      "wsh-message-two": "wsh-message-two 8s cubic-bezier(0.45, 0, 0.25, 1) 0s infinite",
      wiggle: 'wiggle 0.5s ease-in-out',
      'fade-in-up': 'fade-in-up 0.3s ease-out',
      'loader-pulse': 'loader-pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      'card-select': 'card-select 0.25s ease-in-out',
      shake: 'shake 0.3s ease-in-out 0s 2',
      // 三档速度按条数选（类名必须是静态字符串，JIT 扫不到拼出来的动态类名）
      'marquee-y-slow': 'marquee-y 45s linear infinite',
      'marquee-y': 'marquee-y 30s linear infinite',
      'marquee-y-fast': 'marquee-y 18s linear infinite',
    },
  },
  plugins: [
    // eslint-disable-next-line
    require('@tailwindcss/typography'),
    iconsPlugin({
      collections: {
        woot: { icons },
        ...getIconCollections([
          'lucide',
          'logos',
          'ri',
          'ph',
          'material-symbols',
          'teenyicons',
          'fluent',
        ]),
      },
    }),
  ],
};

module.exports = tailwindConfig;
