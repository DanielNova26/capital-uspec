module.exports = {
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 2020, sourceType: 'module' },
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    // Si ves que 'google' te forza indent raro, puedes quitar esta línea:
    'google',
    'plugin:@typescript-eslint/recommended'
  ],
  env: { node: true, es6: true },
  rules: {
    // 2 espacios
    'indent': ['error', 2, { SwitchCase: 1 }],
    // Permite alinear comentarios al final de línea
    'no-multi-spaces': ['error', { ignoreEOLComments: true }],
    // Suavizamos reglas que te estaban rompiendo
    'object-curly-spacing': 'off',
    'comma-dangle': 'off',
    'operator-linebreak': 'off',
    'quotes': 'off',
    'require-jsdoc': 'off',
    'max-len': ['warn', { code: 120, ignoreStrings: true, ignoreTemplateLiterals: true, ignoreComments: true }],
    // TS
    '@typescript-eslint/no-explicit-any': 'off',
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }]
  }
};
console.log("[BUILD] functions v2025-10-09-#2"); // cambia el tag si vuelves a desplegar
