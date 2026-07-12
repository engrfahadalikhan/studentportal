const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const build = process.argv[2] || '114';
const version = process.argv[3] || '2.13.6';
const configPath = `${process.env.USERPROFILE}\\.config\\configstore\\firebase-tools.json`;

const fs = await import('node:fs/promises');
const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const accessToken = config?.tokens?.access_token;
if (!accessToken) {
  throw new Error('Firebase CLI access token was not found.');
}

const fields = {
  min_build: { integerValue: String(build) },
  latest_build: { integerValue: String(build) },
  latest_version: { stringValue: version },
  message: {
    stringValue:
      'Please install the latest AUST Student Portal APK from the coordinator.',
  },
  namespace_collection: { stringValue: 'aust_portal_v2' },
  namespace_document: { stringValue: 'data' },
  updated_at: { timestampValue: new Date().toISOString() },
};

const url =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents/app_control/aust_portal';

const res = await fetch(url, {
  method: 'PATCH',
  headers: {
    authorization: `Bearer ${accessToken}`,
    'content-type': 'application/json',
  },
  body: JSON.stringify({ fields }),
});
const text = await res.text();
if (!res.ok) {
  throw new Error(`${res.status} ${res.statusText}: ${text}`);
}
console.log(text);
