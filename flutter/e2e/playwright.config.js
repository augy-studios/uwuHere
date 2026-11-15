import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 90_000,
  expect: { timeout: 10_000 },
  workers: 1,
  fullyParallel: false,
  reporter: [["list"]],
  use: {
    ...devices["Pixel 7"],
    viewport: { width: 412, height: 915 },
    baseURL: "http://127.0.0.1:47481",
    screenshot: "only-on-failure",
  },
  webServer: [
    { command: "node serve.mjs", url: "http://127.0.0.1:47481", reuseExistingServer: true },
    { command: "node site-serve.mjs", url: "http://127.0.0.1:47482", reuseExistingServer: true },
  ],
});
