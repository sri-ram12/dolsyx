import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  {
    rules: {
      // Downgrade react-hooks rules that flag valid patterns to warnings
      "react-hooks/set-state-in-effect": "warn",
      "react-hooks/purity": "warn",
      "react-hooks/immutability": "warn",
      "react-hooks/exhaustive-deps": "warn",

      // Allow 'any' type — codebase heavily uses it for socket/api data
      "@typescript-eslint/no-explicit-any": "warn",

      // Allow unused vars as warning (unused imports are common during dev)
      "@typescript-eslint/no-unused-vars": "warn",

      // Allow <img> elements (Next.js Image can be adopted later)
      "@next/next/no-img-element": "warn",

      // Allow unescaped apostrophes in JSX text
      "react/no-unescaped-entities": "warn",
    },
  },
]);

export default eslintConfig;
