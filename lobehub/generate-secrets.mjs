#!/usr/bin/env node
// Local recipe helper: writes new secrets; never starts services or contacts a server.
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const output = resolve(process.argv[2] || 'compose.env.local');
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const metadata = { alg: 'RS256', kid: randomBytes(8).toString('hex'), use: 'sig' };
const jwks = (key) => JSON.stringify({ keys: [{ ...key.export({ format: 'jwk' }), ...metadata }] });
const values = {
  LOBEHUB_POSTGRES_PASSWORD: randomBytes(32).toString('hex'),
  LOBEHUB_KEY_VAULTS_SECRET: randomBytes(32).toString('base64'),
  LOBEHUB_AUTH_SECRET: randomBytes(32).toString('hex'),
  LOBEHUB_JWKS_KEY: jwks(privateKey),
  LOBEHUB_JWKS_PUBLIC_KEY: jwks(publicKey),
  LOBEHUB_GATEWAY_SERVICE_TOKEN: randomBytes(32).toString('hex'),
  LOBEHUB_AUTH_ALLOWED_EMAILS: '',
  LOBEHUB_NEWAPI_API_KEY: '',
  LOBEHUB_S3_ACCESS_KEY_ID: '',
  LOBEHUB_S3_SECRET_ACCESS_KEY: '',
};

try {
  writeFileSync(output, Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(''), {
    encoding: 'utf8',
    flag: 'wx',
    mode: 0o600,
  });
  console.log(`Created ${output}. Fill the four blank values, back it up, and import it into Portainer.`);
} catch (error) {
  if (error.code !== 'EEXIST') throw error;
  console.error(`Refusing to overwrite ${output}. Existing deployment secrets must be retained.`);
  process.exitCode = 1;
}
