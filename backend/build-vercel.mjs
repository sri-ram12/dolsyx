import { build } from "esbuild";
import fs from "fs";

await build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  packages: "external",
  outfile: "dist/vercel.cjs",
  footer: {
    js: "\nif (module.exports && module.exports.default) { const _app = module.exports.default; _app.default = _app; module.exports = _app; }\n",
  },
});

fs.writeFileSync("dist/package.json", JSON.stringify({ type: "module" }));
console.log("[Build] Generated dist/vercel.cjs (CommonJS bundle for Vercel Express) and dist/package.json.");
