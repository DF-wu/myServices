#!/usr/bin/env python3
"""Embed the recipe helpers so Portainer CE needs no checkout bind mounts."""

import argparse
import json
from pathlib import Path

import yaml


HERE = Path(__file__).resolve().parent
COMPOSE = HERE.parent / "docker-compose.yml"
MARKER = "# BEGIN MANAGED LIBRECHAT RECIPE — edit librechat/ sources, then run render.py\n"


class RecipeDumper(yaml.SafeDumper):
    pass


def represent_string(dumper, text):
    return dumper.represent_scalar("tag:yaml.org,2002:str", text, style="|" if "\n" in text else None)


RecipeDumper.add_representer(str, represent_string)


def render():
    images = json.loads((HERE / "images.lock.json").read_text())
    seccomp = json.dumps(json.loads((HERE / "nsjail.seccomp.json").read_text()), separators=(",", ":"))
    script = lambda name: (HERE / name).read_text().replace("$", "$$")
    ready = lambda: {"condition": "service_healthy"}
    done = lambda: {"condition": "service_completed_successfully"}
    started = lambda: {"condition": "service_started"}

    def volume(source, target, read_only=False):
        return {"type": "volume", "source": source, "target": target,
                "read_only": read_only, "volume": {"nocopy": True}}

    def bind(source, target, read_only=True):
        return {"type": "bind", "source": source, "target": target,
                "read_only": read_only, "bind": {"create_host_path": False}}

    def auth(role):
        return volume("librechat_code_auth_" + role, "/run/codeauth", True)

    def health(runtime, url, start="20s"):
        code = "fetch('" + url + "').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
        return {"test": ["CMD", runtime, "-e", code], "interval": "15s", "timeout": "5s",
                "retries": 5, "start_period": start}

    def service(image, **options):
        return {"image": images[image], "restart": "unless-stopped",
                "logging": {"driver": "json-file", "options": {"max-size": "10m", "max-file": "3"}},
                **options}

    init_mounts = [volume("librechat_code_keys", "/config/master")]
    roles = ["app", "api", "worker", "egress", "files", "tools", "runner", "redis", "storage"]
    init_mounts += [volume("librechat_code_auth_" + r, "/config/" + r) for r in roles]
    init_mounts += [volume("librechat_code_redis_data", "/config/redis-data"),
                    volume("librechat_code_storage_data", "/config/storage-data")]
    services = {
        "librechat-code-init": service("librechat", restart="no", user="0:0", network_mode="none",
            cap_drop=["ALL"], cap_add=["CHOWN", "DAC_OVERRIDE", "FOWNER"], mem_limit="256m",
            entrypoint=["node", "-e", script("bootstrap.cjs")], volumes=init_mounts),
        "librechat-code-packages": service("code_packages", restart="no", user="0:0",
            mem_limit="2g", cpus=2, entrypoint=["/bin/bash", "-ec", script("prepare-packages.sh")],
            volumes=[volume("librechat_code_packages_v1_10_13", "/runtime")]),
        "librechat": service("librechat", user="3000:3000", init=True,
            ports=["${LIBRECHAT_HOST_BIND:-192.168.10.13}:${LIBRECHAT_HOST_PORT:-43065}:3080"],
            entrypoint=["/bin/sh", "-ec"], command=[
                "set -a\n. /run/codeauth/auth.env\nset +a\n"
                'node -e "$$LIBRECHAT_RECIPE_CONFIG_SCRIPT"\nexec npm run backend'],
            environment={
                "HOST": "0.0.0.0", "PORT": "3080", "NODE_ENV": "production", "TZ": "Asia/Taipei",
                "ENDPOINTS": "custom,agents", "ALLOW_EMAIL_LOGIN": "true", "ALLOW_REGISTRATION": "false",
                "ALLOW_SOCIAL_LOGIN": "false", "ALLOW_SOCIAL_REGISTRATION": "false",
                "MONGO_URI": "mongodb://librechat-mongodb:27017/LibreChat",
                "SEARCH": "true", "MEILI_HOST": "http://librechat-meilisearch:7700",
                "RAG_API_URL": "http://librechat-rag-api:8000",
                "LIBRECHAT_TEMP_CREDENTIALS_PATH": "/app/data/.env.temp",
                "CONFIG_PATH": "/app/data/librechat.recipe.yaml",
                "LIBRECHAT_RECIPE_CONFIG_SCRIPT": script("prepare-config.cjs"),
                "LIBRECHAT_CODE_BASEURL": "http://librechat-code-api:3112/v1",
                "LIBRECHAT_CODE_API_KEY": "", "CODEAPI_AUTH_PROVIDER": "librechat-jwt",
                "CODEAPI_JWT_ENABLED": "true", "CODEAPI_JWT_ALGORITHM": "EdDSA",
                "CODEAPI_JWT_KID": "chatstack-codeapi-2026-10", "CODEAPI_JWT_ISSUER": "librechat",
                "CODEAPI_JWT_AUDIENCE": "codeapi", "CODEAPI_JWT_TTL_SECONDS": "300",
                "CODEAPI_JWT_SINGLE_TENANT_ID": "legacy", "LIBRECHAT_CODE_SANDBOX_OUTPUT_MAX_SIZE": "65536",
            },
            volumes=[
                bind("/mnt/appdata/ChatStack/librechat/config/app.env", "/app/.env"),
                bind("/mnt/appdata/ChatStack/librechat/config/librechat.yaml", "/run/librechat/librechat.yaml"),
                bind("/mnt/appdata/ChatStack/librechat/images", "/app/client/public/images", False),
                bind("/mnt/appdata/ChatStack/librechat/uploads", "/app/uploads", False),
                bind("/mnt/appdata/ChatStack/librechat/logs", "/app/logs", False),
                bind("/mnt/appdata/ChatStack/librechat/skill", "/app/skill", False),
                bind("/mnt/appdata/ChatStack/librechat/data", "/app/data", False), auth("app")],
            networks=["default", "librechat-backend"],
            depends_on={"librechat-code-init": done(), "librechat-mongodb": ready(),
                        "librechat-meilisearch": ready(), "librechat-rag-api": ready(),
                        "librechat-code-api": ready(), "new-api": ready()},
            healthcheck=health("node", "http://127.0.0.1:3080/health", "90s")),
        "librechat-mongodb": service("mongo", command=["mongod", "--noauth", "--bind_ip_all"],
            networks=["librechat-backend"],
            volumes=["librechat_mongodb_data:/data/db", "librechat_mongodb_config:/data/configdb"],
            healthcheck={"test": ["CMD", "mongosh", "--quiet", "--eval", "quit(db.adminCommand('ping').ok ? 0 : 1)"],
                         "interval": "15s", "timeout": "5s", "retries": 5, "start_period": "30s"}),
        "librechat-meilisearch": service("meili", networks=["librechat-backend"],
            entrypoint=["/bin/sh", "-ec"],
            command=["set -a\n. /run/librechat/meili.env\nset +a\nexec /bin/meilisearch"],
            environment={"MEILI_ENV": "production", "MEILI_NO_ANALYTICS": "true"},
            volumes=["librechat_meili_data_v1_35_1:/meili_data",
                     bind("/mnt/appdata/ChatStack/librechat/config/meili.env", "/run/librechat/meili.env")],
            healthcheck={"test": ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:7700/health"],
                         "interval": "15s", "timeout": "5s", "retries": 5, "start_period": "30s"}),
        "librechat-rag-api": service("rag", networks=["default", "librechat-backend"],
            environment={"TZ": "Asia/Taipei", "RAG_HOST": "0.0.0.0", "RAG_PORT": "8000",
                         "DB_HOST": "chatstack-postgres17-pgvector", "DB_PORT": "5432",
                         "POSTGRES_DB": "librechat_rag", "POSTGRES_USER": "librechat_rag",
                         "EMBEDDINGS_PROVIDER": "openai", "EMBEDDINGS_MODEL": "qwen3-embedding-8b",
                         "RAG_OPENAI_BASEURL": "http://new-api:3000/v1", "RAG_CHECK_EMBEDDING_CTX_LENGTH": "false",
                         "SCARF_NO_ANALYTICS": "true"},
            volumes=["librechat_rag_uploads:/app/uploads",
                     bind("/mnt/appdata/ChatStack/librechat/config/rag.env", "/app/.env")],
            depends_on={"chatstack-postgres17-pgvector": started(), "new-api": ready()},
            healthcheck={"test": ["CMD", "python", "-c",
                "import json,urllib.request; r=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=4); "
                "assert r.status == 200 and json.load(r) == {'status':'UP'}"],
                "interval": "20s", "timeout": "5s", "retries": 5, "start_period": "60s"}),
    }

    shared_env = {"TZ": "Asia/Taipei", "LOCAL_MODE": "false", "CODEAPI_HARDENED_SANDBOX_MODE": "true",
                  "CODEAPI_EXECUTION_PROFILE": "default", "CODEAPI_SANDBOX_BACKEND": "http",
                  "CODEAPI_RUNTIME_SESSION_MODE": "stateless", "CODEAPI_BRIDGE_AUTH_MODE": "static",
                  "CODEAPI_BRIDGE_DYNAMIC_WORKERS": "false", "REDIS_HOST": "librechat-code-redis", "REDIS_PORT": "6379",
                  "EGRESS_GATEWAY_URL": "http://librechat-code-egress:3190",
                  "FILE_SERVER_URL": "http://librechat-code-files:3000",
                  "TOOL_CALL_SERVER_URL": "http://librechat-code-tools:3033",
                  "SANDBOX_ENDPOINT": "http://librechat-code-runner:2000/api/v2"}

    def code_service(image, role, command, environment=None, depends=None, url=None):
        return service(image, user="1000:1000", init=True, networks=["librechat-code"],
            cap_drop=["ALL"], security_opt=["no-new-privileges:true"],
            mem_limit="768m", pids_limit=128,
            entrypoint=["/bin/sh", "-ec"],
            command=["set -a\n. /run/codeauth/auth.env\nset +a\nexec " + command],
            environment={**shared_env, **(environment or {})}, volumes=[auth(role)],
            depends_on={"librechat-code-init": done(), "librechat-code-redis": ready(), **(depends or {})},
            **({"healthcheck": health("bun", url)} if url else {}))

    services["librechat-code-api"] = code_service("code_api", "api", "bun run .build-api/api-server.js",
        {"SERVICE_PORT": "3112", "CODEAPI_AUTH_PROVIDER": "librechat-jwt", "CODEAPI_JWT_ISSUER": "librechat",
         "CODEAPI_JWT_AUDIENCE": "codeapi", "CODEAPI_JWT_ALLOWED_ALGS": "EdDSA", "CODEAPI_JWT_SINGLE_TENANT_ID": "legacy"},
        {"librechat-code-worker": ready(), "librechat-code-files": ready(), "librechat-code-tools": ready()},
        "http://127.0.0.1:3112/v1/health")
    services["librechat-code-api"]["networks"].append("librechat-backend")
    services["librechat-code-worker"] = code_service("code_worker", "worker", "bun run .build-worker/worker-server.js",
        {"WORKER_HEALTH_PORT": "3113", "PYTHON_CONCURRENCY": "1", "OTHER_CONCURRENCY": "1", "JOB_TIMEOUT": "300000"},
        {"librechat-code-runner": ready()}, "http://127.0.0.1:3113/ready")
    services["librechat-code-egress"] = code_service("code_egress", "egress", "bun run src/egress-gateway.ts",
        {"EGRESS_GATEWAY_PORT": "3190", "CODEAPI_EGRESS_LEDGER_REQUIRED": "true",
         "EGRESS_GATEWAY_FILE_SERVER_URL": "http://librechat-code-files:3000",
         "EGRESS_GATEWAY_TOOL_CALL_SERVER_URL": "http://librechat-code-tools:3033"},
        {"librechat-code-files": ready(), "librechat-code-tools": ready()}, "http://127.0.0.1:3190/health")
    services["librechat-code-files"] = code_service("code_files", "files", "bun run .build/file-server.js",
        {"FILE_SERVER_PORT": "3000", "MINIO_BUCKET": "librechat-code", "MINIO_ENDPOINT": "librechat-code-storage",
         "MINIO_PORT": "9000", "MINIO_USE_SSL": "false", "MINIO_REGION": "us-east-1"},
        {"librechat-code-storage": ready()}, "http://127.0.0.1:3000/ready")
    # The tool-call-server image imports only its own service sources, so it
    # does not need (or receive) the application or sandbox signing credentials.
    services["librechat-code-tools"] = code_service("code_tools", "tools", "bun run src/tool-call-server.ts",
        {"TOOL_CALL_SERVER_PORT": "3033", "TOOL_CALL_REQUEST_TIMEOUT": "300000", "TOOL_CALL_SESSION_EXPIRY": "600"},
        url="http://127.0.0.1:3033/health")
    services["librechat-code-runner"] = service("code_runner", user="0:0", init=True,
        networks=["librechat-code"], mem_limit="6g", cpus=2, pids_limit=512,
        cap_drop=["ALL"], cap_add=["SYS_ADMIN", "SYS_CHROOT", "SYS_PTRACE", "SETUID", "SETGID",
            "NET_ADMIN", "DAC_OVERRIDE", "DAC_READ_SEARCH", "CHOWN", "FOWNER", "FSETID", "KILL", "SETFCAP", "MKNOD"],
        security_opt=["seccomp=" + seccomp],
        entrypoint=["/bin/bash", "-ec"],
        command=["set -a\n. /run/codeauth/auth.env\nset +a\nexec /usr/local/bin/entrypoint.sh"],
        environment={"TZ": "Asia/Taipei", "KVM_ENABLED": "false", "SANDBOX_USE_CGROUPV2": "false",
            "SANDBOX_REMOVE_UMOUNT_AFTER_STARTUP": "false", "CODEAPI_HARDENED_SANDBOX_MODE": "true",
            "SANDBOX_REQUIRE_EGRESS_MANIFEST": "true", "EGRESS_GATEWAY_URL": "http://librechat-code-egress:3190",
            "SANDBOX_FORWARD_TARGET": "librechat-code-egress:3190", "SANDBOX_ALLOWED_LOCAL_NETWORK_PORT": "3190",
            "SANDBOX_PACKAGES_DIRECTORY": "/pkgs", "SANDBOX_OUTPUT_MAX_SIZE": "65536",
            "SANDBOX_RUN_TIMEOUT": "300000", "SANDBOX_RUN_CPU_TIME": "300000",
            "SANDBOX_COMPILE_TIMEOUT": "30000", "SANDBOX_MAX_CONCURRENT_JOBS": "2",
            "SANDBOX_PER_JOB_UIDS": "true", "SANDBOX_JOB_UID_BASE": "200000", "SANDBOX_JOB_GID_BASE": "200000",
            "SANDBOX_RLIMIT_AS": "16384", "SANDBOX_RLIMIT_FSIZE": "100", "SANDBOX_LOG_LEVEL": "INFO"},
        volumes=[volume("librechat_code_packages_v1_10_13", "/host-packages", True), auth("runner")],
        depends_on={"librechat-code-init": done(), "librechat-code-packages": done(), "librechat-code-egress": ready()},
        healthcheck=health("/sandbox-rootfs/usr/local/bin/bun", "http://127.0.0.1:2000/api/v2/runtimes", "30s"))
    # Host-side healthchecks still run in Fedora; use its curl, not a guest Bun
    # binary whose Debian dynamic linker exists only inside the runner namespace.
    services["librechat-code-runner"]["healthcheck"]["test"] = ["CMD", "curl", "-fsS", "http://127.0.0.1:2000/api/v2/runtimes"]
    services["librechat-code-redis"] = service("redis", user="1000:1000", networks=["librechat-code"],
        mem_limit="384m", command=["redis-server", "/run/codeauth/redis.conf"],
        volumes=[auth("redis"), volume("librechat_code_redis_data", "/data")],
        depends_on={"librechat-code-init": done()},
        healthcheck={"test": ["CMD-SHELL", ". /run/codeauth/auth.env; REDISCLI_AUTH=\"$$REDIS_PASSWORD\" redis-cli ping | grep -qx PONG"],
                     "interval": "10s", "timeout": "5s", "retries": 5})
    services["librechat-code-storage"] = service("storage", user="1000:1000", networks=["librechat-code"],
        mem_limit="1g", entrypoint=["/bin/sh", "-ec"],
        command=["set -a\n. /run/codeauth/auth.env\nset +a\nexec /usr/bin/rustfs /data"],
        environment={"RUSTFS_ADDRESS": ":9000", "RUSTFS_CONSOLE_ENABLE": "false",
                     "RUSTFS_OBS_LOG_DIRECTORY": "/data/.logs", "RUSTFS_OBS_LOGGER_LEVEL": "warn", "TZ": "Asia/Taipei"},
        volumes=[auth("storage"), volume("librechat_code_storage_data", "/data")],
        depends_on={"librechat-code-init": done()},
        healthcheck={"test": ["CMD", "curl", "-fsS", "http://127.0.0.1:9000/health/ready"],
                     "interval": "10s", "timeout": "5s", "retries": 12, "start_period": "30s"})

    volumes = {name: {"external": True, "name": "chatstack_" + name} for name in (
        "librechat_mongodb_data", "librechat_mongodb_config", "librechat_meili_data_v1_35_1", "librechat_rag_uploads")}
    for mount in init_mounts + services["librechat-code-packages"]["volumes"]:
        volumes[mount["source"]] = {}
    doc = {"services": services, "networks": {"default": {}, "librechat-backend": {"internal": True},
            "librechat-code": {"internal": True}}, "volumes": volumes}
    generated = yaml.dump(doc, Dumper=RecipeDumper, sort_keys=False, allow_unicode=True, width=120)
    base = COMPOSE.read_text().split(MARKER)[0].rstrip() + "\n\n"
    # Everything before the marker remains the hand-maintained ChatStack services.
    return base + MARKER + generated.removeprefix("services:\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = render()
    if args.check:
        if COMPOSE.read_text() != content:
            raise SystemExit("LibreChat embedded recipe is stale; run ChatStack/librechat/render.py")
        print("LibreChat embedded recipe is current.")
    else:
        COMPOSE.write_text(content)
        print("Updated only the managed LibreChat recipe block.")
