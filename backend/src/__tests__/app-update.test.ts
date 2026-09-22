import { test, describe } from "node:test";
import assert from "node:assert";
import express from "express";
import appRoutes from "../routes/app.routes.js";
import fs from "node:fs";
import path from "node:path";

describe("DOLSYX App Auto-Update Backend Tests", () => {
  const app = express();
  app.use(express.json());
  app.use("/api/app", appRoutes);

  test("GET /api/app/version returns structured metadata with no-cache headers", async () => {
    // If supertest is not available, we can test the router logic directly
    // Let's create mock req/res
    let statusCode = 200;
    const headers: Record<string, string> = {};
    let responseBody: any = null;

    const req: any = {
      get: (h: string) => (h === "host" ? "localhost:5000" : undefined),
      protocol: "http",
    };
    const res: any = {
      setHeader: (name: string, val: string) => {
        headers[name.toLowerCase()] = val;
      },
      status: (code: number) => {
        statusCode = code;
        return res;
      },
      json: (data: any) => {
        responseBody = data;
        return res;
      },
    };

    // Find the version route handler from appRoutes
    const versionRoute: any = appRoutes.stack.find(
      (layer: any) => layer.route && layer.route.path === "/version" && layer.route.methods.get
    );
    assert.ok(versionRoute && versionRoute.route, "Route /version exists");

    await versionRoute.route.stack[0].handle(req, res, () => {});

    assert.strictEqual(statusCode, 200);
    assert.strictEqual(headers["cache-control"], "no-store, no-cache, must-revalidate, proxy-revalidate");
    assert.strictEqual(headers["pragma"], "no-cache");
    assert.strictEqual(headers["expires"], "0");

    assert.ok(responseBody, "Response body should not be null");
    assert.strictEqual(responseBody.success, true);
    assert.strictEqual(responseBody.version, "1.0.4");
    assert.strictEqual(responseBody.buildNumber, 4);
    assert.strictEqual(responseBody.minimumSupportedVersion, "1.0.0");
    assert.strictEqual(responseBody.minimumSupportedBuild, 1);
    assert.strictEqual(responseBody.updateRequired, false);
    assert.ok(typeof responseBody.downloadUrl === "string");
  });

  test("Verify update-config.json exists and contains correct release metadata", () => {
    const configPath = path.resolve(process.cwd(), "update-config.json");
    assert.ok(fs.existsSync(configPath), "update-config.json exists");

    const content = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    assert.strictEqual(content.version, "1.0.4");
    assert.strictEqual(content.buildNumber, 4);
    assert.strictEqual(content.minimumSupportedVersion, "1.0.0");
    assert.strictEqual(content.minimumSupportedBuild, 1);
  });
});
