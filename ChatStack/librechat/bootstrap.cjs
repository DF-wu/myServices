// Runs only as the recipe's one-shot provisioner when Portainer deploys it.
const fs = require('node:fs');
const path = require('node:path');
const { generateKeyPairSync, randomBytes } = require('node:crypto');

const root = process.env.RECIPE_STATE_DIR || '/config';
const appUid = Number(process.env.LIBRECHAT_UID || 3000);
const appGid = Number(process.env.LIBRECHAT_GID || 3000);
const codeUid = Number(process.env.CODEAPI_UID || 1000);
const codeGid = Number(process.env.CODEAPI_GID || 1000);
for (const id of [appUid, appGid, codeUid, codeGid]) {
  if (!Number.isSafeInteger(id) || id < 0) throw new Error('Invalid recipe UID/GID');
}
const masterDir = path.join(root, 'master');
fs.mkdirSync(masterDir, { recursive: true, mode: 0o700 });
fs.chmodSync(masterDir, 0o700);
const masterFile = path.join(masterDir, 'keys.json');
let keys;
if (fs.existsSync(masterFile)) {
  try {
    keys = JSON.parse(fs.readFileSync(masterFile, 'utf8'));
  } catch {
    throw new Error('Stored Code Interpreter credentials cannot be read; refusing to replace them');
  }
  if (keys.schema !== 1) throw new Error('Unknown Code Interpreter credential schema');
} else {
  const jwt = generateKeyPairSync('ed25519');
  const manifest = generateKeyPairSync('ed25519');
  keys = {
    schema: 1,
    jwtPrivate: Buffer.from(jwt.privateKey.export({ type: 'pkcs8', format: 'pem' })).toString('base64'),
    jwtPublic: jwt.publicKey.export({ format: 'jwk' }),
    manifestPrivate: manifest.privateKey.export({ type: 'pkcs8', format: 'der' }).toString('base64'),
    manifestPublic: manifest.publicKey.export({ type: 'spki', format: 'der' }).toString('base64'),
    redisPassword: randomBytes(32).toString('hex'),
    storageAccess: randomBytes(16).toString('hex'),
    storageSecret: randomBytes(32).toString('hex'),
    internalToken: randomBytes(32).toString('hex'),
    egressSecret: randomBytes(32).toString('hex'),
  };
  fs.writeFileSync(masterFile + '.tmp', JSON.stringify(keys), { mode: 0o600 });
  fs.renameSync(masterFile + '.tmp', masterFile);
}
// A damaged state must fail, never silently rotate a subset of credentials.
for (const key of ['jwtPrivate', 'manifestPrivate', 'manifestPublic', 'redisPassword',
  'storageAccess', 'storageSecret', 'internalToken', 'egressSecret']) {
  if (typeof keys[key] !== 'string' || !keys[key]) throw new Error('Incomplete Code Interpreter credentials');
}
if (!keys.jwtPublic?.x) throw new Error('Incomplete Code Interpreter verifier');
const kid = 'chatstack-codeapi-2026-10';
const redis = { REDIS_PASSWORD: keys.redisPassword };
const internal = { CODEAPI_INTERNAL_SERVICE_TOKEN: keys.internalToken };
const roles = {
  app: { CODEAPI_JWT_PRIVATE_KEY_BASE64: keys.jwtPrivate },
  api: { ...redis, ...internal,
    CODEAPI_JWT_JWKS_JSON: JSON.stringify({ keys: [{ ...keys.jwtPublic, kid, alg: 'EdDSA', use: 'sig' }] }) },
  worker: { ...redis, ...internal, CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY: keys.manifestPrivate },
  egress: { ...redis, ...internal, CODEAPI_EGRESS_GRANT_SECRET: keys.egressSecret },
  files: { ...redis, ...internal, MINIO_ACCESS_KEY: keys.storageAccess, MINIO_SECRET_KEY: keys.storageSecret },
  tools: { ...redis, ...internal },
  runner: { SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY: keys.manifestPublic },
  redis,
  storage: { RUSTFS_ACCESS_KEY: keys.storageAccess, RUSTFS_SECRET_KEY: keys.storageSecret },
};
for (const [role, values] of Object.entries(roles)) {
  const dir = path.join(root, role);
  const publicOnly = role === 'runner';
  const uid = role === 'app' ? appUid : codeUid;
  const gid = role === 'app' ? appGid : codeGid;
  fs.mkdirSync(dir, { recursive: true });
  fs.chmodSync(dir, publicOnly ? 0o755 : 0o700);
  if (!publicOnly) fs.chownSync(dir, uid, gid);
  const lines = Object.entries(values).map(([key, value]) => {
    if (/[\r\n']/.test(value)) throw new Error('Invalid generated environment value');
    return key + "='" + value + "'";
  }).join('\n') + '\n';
  const file = path.join(dir, 'auth.env');
  fs.writeFileSync(file + '.tmp', lines, { mode: publicOnly ? 0o644 : 0o600 });
  fs.chmodSync(file + '.tmp', publicOnly ? 0o644 : 0o600);
  if (!publicOnly) fs.chownSync(file + '.tmp', uid, gid);
  fs.renameSync(file + '.tmp', file);
}
const redisConfig = path.join(root, 'redis', 'redis.conf');
fs.writeFileSync(redisConfig, 'bind 0.0.0.0\nprotected-mode yes\nappendonly yes\n'
  + 'maxmemory 256mb\nmaxmemory-policy noeviction\ndir /data\nrequirepass ' + keys.redisPassword + '\n', { mode: 0o600 });
fs.chownSync(redisConfig, codeUid, codeGid);
for (const data of ['redis-data', 'storage-data']) {
  const dir = path.join(root, data);
  fs.mkdirSync(dir, { recursive: true });
  fs.chownSync(dir, codeUid, codeGid);
}
// The image has symlinks from /opt/rustfs into these data directories.
for (const relative of ['storage-data/.rustfs', 'storage-data/.rustfs/events', 'storage-data/.rustfs/audit']) {
  const dir = path.join(root, relative);
  fs.mkdirSync(dir, { recursive: true });
  fs.chownSync(dir, codeUid, codeGid);
}
console.log('Code Interpreter credentials ready; existing signing keys and passwords preserved.');
