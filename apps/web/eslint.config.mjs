// eslint-config-next 16 ships flat configs (the template had no eslint config
// of its own). This is what `create-next-app` generates for Next 16, with the
// rules that flag the template's code as written turned off rather than the
// code rewritten (see IMPLEMENTATION-STATUS.md).
import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // `ActionState` carries `[key: string]: any`; two imports are unused and
      // the setup script's catch blocks name an `error` they never read; the
      // proxy's `let res` is never reassigned; two JSX strings carry a bare
      // apostrophe — all upstream as written.
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', caughtErrors: 'none' }
      ],
      'prefer-const': 'off',
      'react/no-unescaped-entities': 'off'
    }
  },
  globalIgnores([
    '.next/**',
    '.open-next/**',
    '.wrangler/**',
    'out/**',
    'build/**',
    'next-env.d.ts'
  ])
]);

export default eslintConfig;
