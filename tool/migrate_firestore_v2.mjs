const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const apiKey =
  process.env.FIREBASE_API_KEY || 'AIzaSyDyf9pt9HQfsQxh7FPOYb8jKa9NXwHqwPs';
const namespaceCollection = 'aust_portal_v2';
const namespaceDocument = 'data';
const currentBuild = 114;
const currentVersion = '2.13.6';

const collections = [
  'cloud_fyp_groups',
  'cloud_fyp_panels',
  'cloud_fyp_meetings',
  'cloud_fyp_viva',
  'cloud_fyp_evaluations',
  'cloud_fyp_submissions',
  'cloud_fyp_ideas',
  'cloud_fyp_allocations',
  'cloud_fyp_proposals',
  'cloud_fyp_meetinglogs',
  'cloud_fyp_consents',
  'cloud_fyp_srs',
  'cloud_credentials',
];

const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function withKey(url) {
  return `${url}${url.includes('?') ? '&' : '?'}key=${apiKey}`;
}

async function firestore(url, options = {}) {
  const res = await fetch(withKey(url), {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${text}`);
  }
  return res.json();
}

async function listCollection(collection) {
  const docs = [];
  let pageToken = '';
  do {
    const params = new URLSearchParams({ pageSize: '300' });
    if (pageToken) params.set('pageToken', pageToken);
    const json = await firestore(`${base}/${collection}?${params}`);
    docs.push(...(json.documents || []));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function docId(name) {
  return name.split('/').pop();
}

function withClientMeta(fields = {}) {
  return {
    ...fields,
    client_build: { integerValue: String(currentBuild) },
    client_version: { stringValue: currentVersion },
    client_namespace: {
      stringValue: `${namespaceCollection}/${namespaceDocument}`,
    },
    migrated_at: { timestampValue: new Date().toISOString() },
  };
}

async function writeDocument(path, fields) {
  await firestore(`${base}/${path}`, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
}

async function migrateCollection(collection) {
  const docs = await listCollection(collection);
  let copied = 0;
  for (const doc of docs) {
    const id = docId(doc.name);
    const path = `${namespaceCollection}/${namespaceDocument}/${collection}/${id}`;
    await writeDocument(path, withClientMeta(doc.fields || {}));
    copied += 1;
    if (copied % 100 === 0) {
      console.log(`${collection}: copied ${copied}/${docs.length}`);
    }
  }
  console.log(`${collection}: copied ${copied}`);
  return copied;
}

async function setAppControl() {
  await writeDocument('app_control/aust_portal', {
    min_build: { integerValue: String(currentBuild) },
    latest_build: { integerValue: String(currentBuild) },
    latest_version: { stringValue: currentVersion },
    message: {
      stringValue:
        'Please install the latest AUST Student Portal APK from the coordinator.',
    },
    namespace_collection: { stringValue: namespaceCollection },
    namespace_document: { stringValue: namespaceDocument },
    updated_at: { timestampValue: new Date().toISOString() },
  });
}

let total = 0;
for (const collection of collections) {
  total += await migrateCollection(collection);
}
await setAppControl();
console.log(`Done. Migrated ${total} documents and set min_build=${currentBuild}.`);
