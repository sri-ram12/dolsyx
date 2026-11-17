import { build } from "esbuild";
import fs from "fs";

const moduleResolutionBanner = `
(function () {
  try {
    const _path = require("path");
    const _Module = require("module");
    const _extra = [
      _path.join(__dirname, "backend", "node_modules"),
      _path.join(process.cwd(), "backend", "node_modules"),
      "/var/task/backend/node_modules",
      "/var/task/node_modules"
    ];
    for (const _p of _extra) {
      if (Array.isArray(module.paths) && !module.paths.includes(_p)) {
        module.paths.unshift(_p);
      }
    }
    process.env.NODE_PATH = _extra.concat(process.env.NODE_PATH ? [process.env.NODE_PATH] : []).join(_path.delimiter);
    if (typeof _Module._initPaths === "function") {
      _Module._initPaths();
    }
  } catch (_) {}
})();
`;

await build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  packages: "external",
  outfile: "dist/vercel.cjs",
  banner: {
    js: moduleResolutionBanner,
  },
  footer: {
    js: "\nif (module.exports && module.exports.default) { const _app = module.exports.default; _app.default = _app; module.exports = _app; }\n",
  },
});

fs.writeFileSync("dist/package.json", JSON.stringify({ type: "module" }));
console.log("[Build] Generated dist/vercel.cjs (CommonJS bundle with monorepo module resolution banner) and dist/package.json.");
