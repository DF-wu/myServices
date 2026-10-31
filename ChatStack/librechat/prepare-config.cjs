// Read the original YAML; write an effective copy without changing host appdata.
const fs = require('node:fs');
const { parseEnv } = require('node:util');
const yaml = require('js-yaml');

const legacyEnv = parseEnv(fs.readFileSync(process.env.RECIPE_LEGACY_ENV || '/app/.env', 'utf8'));
for (const [name, length] of [['CREDS_KEY', 64], ['CREDS_IV', 32]]) {
  if (!new RegExp('^[a-fA-F0-9]{' + length + '}$').test(legacyEnv[name] || '')) {
    throw new Error('Existing LibreChat ' + name + ' is missing or invalid; refusing to replace it');
  }
}
for (const name of ['JWT_SECRET', 'JWT_REFRESH_SECRET', 'MEILI_MASTER_KEY', 'DF_LLM_API_KEY']) {
  if (!legacyEnv[name]) throw new Error('Existing LibreChat ' + name + ' is required');
}
const config = yaml.load(fs.readFileSync(process.env.RECIPE_LEGACY_CONFIG || '/run/librechat/librechat.yaml', 'utf8'));
if (!config || typeof config !== 'object' || !Array.isArray(config.endpoints?.custom)) {
  throw new Error('Existing LibreChat custom endpoints are missing; refusing an empty replacement');
}
config.endpoints.agents ||= {};
const capabilities = new Set(config.endpoints.agents.capabilities || [
  'file_search', 'artifacts', 'actions', 'tools', 'context', 'skills',
]);
for (const value of ['execute_code', 'run_in_background', 'programmatic_tools']) capabilities.add(value);
// The local HTTP backend is stateless. A stateful toggle without a backend fails.
capabilities.delete('stateful_code_sessions');
config.endpoints.agents.capabilities = [...capabilities];
const output = process.env.CONFIG_PATH || '/app/data/librechat.recipe.yaml';
fs.writeFileSync(output, yaml.dump(config, { lineWidth: 120 }), { mode: 0o600 });
console.log('LibreChat effective configuration prepared; original YAML and endpoint credentials preserved.');
