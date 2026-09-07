// 直接复用主仓的紫玻璃色板与图标集，保证 App 与网页端视觉一致（不另起一套设计 token）。
import { colors } from '../theme/colors';
import { icons } from '../theme/icons';
const {
  iconsPlugin,
  getIconCollections,
} = require('@egoist/tailwindcss-icons');

export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {
      colors: { ...colors },
      fontFamily: {
        sans: [
          '-apple-system',
          'system-ui',
          'BlinkMacSystemFont',
          '"PingFang SC"',
          '"Helvetica Neue"',
          'sans-serif',
        ],
      },
      spacing: {
        // 刘海/home 指示条安全区，供 pt-safe / pb-safe 使用
        safeTop: 'env(safe-area-inset-top)',
        safeBottom: 'env(safe-area-inset-bottom)',
      },
    },
  },
  plugins: [
    iconsPlugin({
      collections: { woot: { icons }, ...getIconCollections(['lucide', 'ri', 'ph']) },
    }),
  ],
};
