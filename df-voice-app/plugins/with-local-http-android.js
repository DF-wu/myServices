const fs = require("node:fs");
const path = require("node:path");

const {
  createRunOncePlugin,
  withAndroidManifest,
  withDangerousMod,
} = require("expo/config-plugins");

const pkg = require("../package.json");

const GRADLE_DISTRIBUTION_URL =
  "https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip";

function pinGradleWrapper(wrapperPath) {
  if (!fs.existsSync(wrapperPath)) {
    return;
  }

  const current = fs.readFileSync(wrapperPath, "utf8");
  const next = /^distributionUrl=.*$/m.test(current)
    ? current.replace(
        /^distributionUrl=.*$/m,
        `distributionUrl=${GRADLE_DISTRIBUTION_URL}`,
      )
    : `${current.trimEnd()}\ndistributionUrl=${GRADLE_DISTRIBUTION_URL}\n`;
  fs.writeFileSync(wrapperPath, next);
}

function withLocalHttpAndroid(config) {
  config = withAndroidManifest(config, (nextConfig) => {
    const application = nextConfig.modResults.manifest.application?.[0];
    if (application) {
      application.$ = application.$ || {};
      application.$["android:usesCleartextTraffic"] = "true";
    }
    return nextConfig;
  });
  config = withDangerousMod(config, [
    "android",
    async (nextConfig) => {
      const wrapperPath = path.join(
        nextConfig.modRequest.platformProjectRoot,
        "gradle",
        "wrapper",
        "gradle-wrapper.properties",
      );
      pinGradleWrapper(wrapperPath);
      return nextConfig;
    },
  ]);
  return config;
}

module.exports = createRunOncePlugin(
  withLocalHttpAndroid,
  "with-local-http-android",
  pkg.version,
);
