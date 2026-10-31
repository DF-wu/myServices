"""Recipe checks only. Never creates, starts, or execs into a container."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


COMPOSE = Path(__file__).resolve().parents[1] / "docker-compose.yml"
HAS_NODE_YAML = subprocess.run(
    ["node", "-e", "require('js-yaml')"], capture_output=True,
).returncode == 0


class RecipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recipe = yaml.safe_load(COMPOSE.read_text())

    def test_restore_uses_existing_database_volumes(self):
        services = self.recipe["services"]
        self.assertTrue("librechat" in services, "LibreChat must be in the Portainer recipe")
        for name in (
            "librechat_mongodb_data", "librechat_mongodb_config",
            "librechat_meili_data_v1_35_1", "librechat_rag_uploads",
        ):
            volume = self.recipe["volumes"][name]
            self.assertTrue(volume["external"], "Missing old data must not create an empty replacement")
            self.assertEqual(volume["name"], "chatstack_" + name)

    def test_execution_does_not_expose_host_or_control_secrets(self):
        services = self.recipe["services"]
        self.assertTrue("librechat-code-runner" in services, "A real sandbox is required")
        for name, service in services.items():
            if not name.startswith("librechat"):
                continue
            self.assertNotIn("build", service, "Portainer must pull prebuilt images")
            self.assertNotIn("env_file", service, "Portainer cannot read host-only env files")
            if name != "librechat":
                self.assertFalse(service.get("ports"), name)
            for mount in service.get("volumes", []):
                self.assertNotIn("docker.sock", str(mount))
        runner = services["librechat-code-runner"]
        self.assertFalse(runner.get("privileged", False))
        self.assertFalse(runner.get("devices"), "This host has no /dev/kvm")
        for key in runner["environment"]:
            self.assertFalse(any(s in key for s in ("PRIVATE_KEY", "PASSWORD", "SECRET", "TOKEN")), key)
        self.assertTrue(self.recipe["networks"]["librechat-code"]["internal"])
        profile = next(x for x in runner["security_opt"] if x.startswith("seccomp="))
        self.assertEqual(json.loads(profile.split("=", 1)[1])["defaultAction"], "SCMP_ACT_ERRNO")

    def test_initializer_can_repair_permissions_after_role_ownership_changes(self):
        init = self.recipe["services"]["librechat-code-init"]
        self.assertEqual(init["user"], "0:0")
        self.assertTrue({"CHOWN", "DAC_OVERRIDE", "FOWNER"}.issubset(init["cap_add"]),
                        "Root needs FOWNER to chmod the directories already owned by UID 1000/3000")
        self.assertEqual(init["network_mode"], "none")

    def test_bootstrap_reuses_keys_and_only_runner_gets_public_manifest_key(self):
        self.assertTrue("librechat-code-init" in self.recipe["services"], "Persistent key provisioning is required")
        script = self.recipe["services"]["librechat-code-init"]["entrypoint"][2].replace("$$", "$")
        with tempfile.TemporaryDirectory(prefix="librechat-recipe-test-") as root:
            env = {
                **os.environ, "RECIPE_STATE_DIR": root,
                "LIBRECHAT_UID": str(os.getuid()), "LIBRECHAT_GID": str(os.getgid()),
                "CODEAPI_UID": str(os.getuid()), "CODEAPI_GID": str(os.getgid()),
            }
            def provision():
                result = subprocess.run(["node", "-e", script], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("PRIVATE KEY", result.stdout + result.stderr)
                return {p.relative_to(root): p.read_bytes() for p in Path(root).rglob("*.env")}
            first = provision()
            self.assertTrue(first)
            self.assertEqual(first, provision(), "Redeploying must not rotate credentials")
            app = (Path(root) / "app/auth.env").read_text()
            api = (Path(root) / "api/auth.env").read_text()
            worker = (Path(root) / "worker/auth.env").read_text()
            runner = (Path(root) / "runner/auth.env").read_text()
            self.assertIn("CODEAPI_JWT_PRIVATE_KEY_BASE64=", app)
            self.assertIn("CODEAPI_JWT_JWKS_JSON=", api)
            self.assertNotIn("PRIVATE_KEY", api)
            self.assertIn("CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY=", worker)
            self.assertIn("SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY=", runner)
            for term in ("PRIVATE_KEY", "PASSWORD", "TOKEN", "SECRET", "REDIS_", "MINIO_"):
                self.assertNotIn(term, runner)
            # Validate actual generated key pairs, not just variable names.
            check = r"""
const fs = require('node:fs');
const { parseEnv } = require('node:util');
const { createPrivateKey, createPublicKey, sign, verify } = require('node:crypto');
const read = role => parseEnv(fs.readFileSync(`${process.env.RECIPE_STATE_DIR}/${role}/auth.env`, 'utf8'));
const app = read('app'), api = read('api'), worker = read('worker'), runner = read('runner');
const message = Buffer.from('recipe authentication contract');
const jwtKey = createPrivateKey(Buffer.from(app.CODEAPI_JWT_PRIVATE_KEY_BASE64, 'base64'));
const jwtPublic = createPublicKey({key: JSON.parse(api.CODEAPI_JWT_JWKS_JSON).keys[0], format: 'jwk'});
const manifestKey = createPrivateKey({key: Buffer.from(worker.CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY, 'base64'), format: 'der', type: 'pkcs8'});
const manifestPublic = createPublicKey({key: Buffer.from(runner.SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY, 'base64'), format: 'der', type: 'spki'});
if (!verify(null, message, jwtPublic, sign(null, message, jwtKey))) process.exit(1);
if (!verify(null, message, manifestPublic, sign(null, message, manifestKey))) process.exit(1);
"""
            result = subprocess.run(["node", "-e", check], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

            master = Path(root) / "master/keys.json"
            corrupt = '{"jwtPrivate":"test-private-material",broken'
            master.write_text(corrupt)
            failed = subprocess.run(["node", "-e", script], env=env, capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertNotIn("test-private-material", failed.stderr)
            self.assertEqual(master.read_text(), corrupt, "Damaged keys must not be replaced")

    @unittest.skipUnless(HAS_NODE_YAML, "Set NODE_PATH to a js-yaml installation to check config merging")
    def test_effective_config_keeps_custom_endpoints_and_legacy_file_unchanged(self):
        script = self.recipe["services"]["librechat"]["environment"]["LIBRECHAT_RECIPE_CONFIG_SCRIPT"].replace("$$", "$")
        with tempfile.TemporaryDirectory(prefix="librechat-config-test-") as root:
            root = Path(root)
            config = root / "original.yaml"
            original = {
                "version": "1.3.17", "interface": {"fileSearch": True},
                "endpoints": {"custom": [{"name": "DF-Gateway", "apiKey": "${DF_LLM_API_KEY}",
                    "baseURL": "http://new-api:3000/v1", "models": {"default": ["gpt-4.1-mini"], "fetch": True}}],
                    "agents": {"recursionLimit": 77, "capabilities": ["tools", "stateful_code_sessions"]}},
            }
            config.write_text(yaml.safe_dump(original))
            original_bytes = config.read_bytes()
            credentials = root / "original.env"
            credentials.write_text("CREDS_KEY=" + "a" * 64 + "\nCREDS_IV=" + "b" * 32
                + "\nJWT_SECRET=test-login\nJWT_REFRESH_SECRET=test-refresh\n"
                + "MEILI_MASTER_KEY=test-search-key\nDF_LLM_API_KEY=test-gateway\n")
            output = root / "effective.yaml"
            env = {**os.environ, "RECIPE_LEGACY_ENV": str(credentials),
                   "RECIPE_LEGACY_CONFIG": str(config), "CONFIG_PATH": str(output)}
            result = subprocess.run(["node", "-e", script], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(config.read_bytes(), original_bytes)
            effective = yaml.safe_load(output.read_text())
            self.assertEqual(effective["endpoints"]["custom"], original["endpoints"]["custom"])
            self.assertEqual(effective["endpoints"]["agents"]["recursionLimit"], 77)
            self.assertEqual(set(effective["endpoints"]["agents"]["capabilities"]),
                             {"tools", "execute_code", "run_in_background", "programmatic_tools"})
            self.assertNotIn("test-gateway", output.read_text())
            # Missing legacy encryption keys must fail before creating a replacement.
            output.unlink()
            credentials.write_text("CREDS_KEY=\nCREDS_IV=\n")
            result = subprocess.run(["node", "-e", script], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_embedded_sources_and_compose_interpolation(self):
        here = COMPOSE.parent / "librechat"
        check = subprocess.run(["python3", str(here / "render.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        result = subprocess.run(["docker", "compose", "-f", str(COMPOSE), "config", "--format", "json"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        services = json.loads(result.stdout)["services"]
        # `compose config` escapes literal dollars again for round-trip serialization.
        for name, filename in [("librechat-code-init", "bootstrap.cjs"),
                               ("librechat-code-packages", "prepare-packages.sh")]:
            actual = services[name]["entrypoint"][-1].replace("$$", "$")
            self.assertEqual(actual, (here / filename).read_text())
        actual = services["librechat"]["environment"]["LIBRECHAT_RECIPE_CONFIG_SCRIPT"].replace("$$", "$")
        self.assertEqual(actual, (here / "prepare-config.cjs").read_text())
        for name, service in services.items():
            if name.startswith("librechat") and service.get("command"):
                command = service["command"][-1].replace("$$", "$")
                if "\n" in command:
                    shell = subprocess.run(["bash", "-n"], input=command, capture_output=True, text=True)
                    self.assertEqual(shell.returncode, 0, name + ": " + shell.stderr)


if __name__ == "__main__":
    unittest.main()
