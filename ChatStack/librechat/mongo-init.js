// Runs once on a NEW Mongo data directory via the official image entrypoint.
// The application uses this restricted account, never the bootstrap root account.
const appPassword = process.env.LIBRECHAT_MONGO_APP_PASSWORD;
if (!appPassword || !/^[0-9a-fA-F]+$/.test(appPassword)) {
  throw new Error('LIBRECHAT_MONGO_APP_PASSWORD must be a nonempty hex password');
}
const appDatabase = db.getSiblingDB('LibreChat');
appDatabase.createUser({
  user: 'librechat_app',
  pwd: appPassword,
  roles: [{ role: 'readWrite', db: 'LibreChat' }],
});
