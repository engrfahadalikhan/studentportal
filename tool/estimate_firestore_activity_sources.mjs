const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const configPath = `${process.env.USERPROFILE}\\.config\\configstore\\firebase-tools.json`;

const fs = await import('node:fs/promises');
const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const accessToken = config?.tokens?.access_token;
if (!accessToken) throw new Error('Firebase CLI access token was not found.');

const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const windows = [
  { key: 'last20Minutes', minutes: 20 },
  { key: 'last60Minutes', minutes: 60 },
  { key: 'quotaDay', start: new Date('2026-07-07T07:00:00.000Z') },
];

const rootCollections = [
  'attendance_scans',
  'exam_students',
  'exam_halls',
  'exam_sheets',
  'exam_records',
  'exam_ufm',
  'exam_deleted',
  'cloud_assignments',
  'cloud_submissions',
  'cloud_paper_batches',
  'slot_slots',
  'slot_rows',
  'slot_receipts',
  'slot_contributions',
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

async function api(url) {
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await res.text();
  if (!res.ok) {
    if (res.status === 404 || res.status === 403) return null;
    throw new Error(`${res.status} ${res.statusText}: ${text}`);
  }
  return JSON.parse(text);
}

async function list(path) {
  const docs = [];
  let pageToken = '';
  do {
    const params = new URLSearchParams({ pageSize: '300' });
    if (pageToken) params.set('pageToken', pageToken);
    const json = await api(`${base}/${path}?${params}`);
    if (!json) break;
    docs.push(...(json.documents || []));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function scalar(v) {
  if (!v || typeof v !== 'object') return undefined;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return String(v.integerValue);
  if ('doubleValue' in v) return String(v.doubleValue);
  if ('booleanValue' in v) return String(v.booleanValue);
  if ('timestampValue' in v) return v.timestampValue;
  return undefined;
}

function field(fields, name) {
  return scalar(fields?.[name]);
}

function jsonData(fields) {
  const raw = field(fields, 'data');
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function add(set, value) {
  const v = (value || '').toString().trim();
  if (v) set.add(v);
}

function makeBucket() {
  return {
    docsUpdated: 0,
    collections: new Map(),
    clientBuilds: new Set(),
    clientVersions: new Set(),
    uploadedBy: new Set(),
    deviceNames: new Set(),
    actorNames: new Set(),
    rolls: new Set(),
  };
}

function record(bucket, collection, doc) {
  bucket.docsUpdated += 1;
  bucket.collections.set(collection, (bucket.collections.get(collection) || 0) + 1);
  const f = doc.fields || {};
  const d = jsonData(f);
  add(bucket.clientBuilds, field(f, 'client_build'));
  add(bucket.clientVersions, field(f, 'client_version'));
  add(bucket.uploadedBy, field(f, 'uploaded_by'));
  add(bucket.deviceNames, field(f, 'deviceName') || field(f, 'device_name'));
  add(bucket.actorNames, field(f, 'byName'));
  add(bucket.actorNames, field(f, 'teacherName'));
  add(bucket.actorNames, d.createdByName);
  add(bucket.actorNames, d.supervisorName);
  add(bucket.rolls, field(f, 'student_id'));
  add(bucket.rolls, d.createdByName);
  if (Array.isArray(d.members)) {
    for (const member of d.members) add(bucket.rolls, member.rollNo);
  }
}

function summarize(bucket) {
  const topCollections = [...bucket.collections.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 12)
    .map(([collection, count]) => ({ collection, count }));
  const sample = (set) => [...set].sort().slice(0, 25);
  return {
    docsUpdated: bucket.docsUpdated,
    topCollections,
    distinctClientBuilds: sample(bucket.clientBuilds),
    distinctClientVersions: sample(bucket.clientVersions),
    distinctUploadedByCount: bucket.uploadedBy.size,
    uploadedBySample: sample(bucket.uploadedBy),
    distinctDeviceNameCount: bucket.deviceNames.size,
    deviceNameSample: sample(bucket.deviceNames),
    distinctActorNameCount: bucket.actorNames.size,
    actorNameSample: sample(bucket.actorNames),
    distinctRollCount: bucket.rolls.size,
    rollSample: sample(bucket.rolls),
  };
}

const now = new Date();
const buckets = Object.fromEntries(windows.map((w) => [w.key, makeBucket()]));
const paths = [
  ...rootCollections.map((c) => ({ label: `root/${c}`, path: c })),
  ...rootCollections.map((c) => ({
    label: `v2/${c}`,
    path: `aust_portal_v2/data/${c}`,
  })),
];

for (const { label, path } of paths) {
  const docs = await list(path);
  for (const doc of docs) {
    const updated = new Date(doc.updateTime || doc.createTime || 0);
    for (const w of windows) {
      const start = w.start || new Date(now.getTime() - w.minutes * 60 * 1000);
      if (updated >= start && updated <= now) record(buckets[w.key], label, doc);
    }
  }
}

console.log(
  JSON.stringify(
    {
      projectId,
      now: now.toISOString(),
      windows: Object.fromEntries(
        Object.entries(buckets).map(([key, bucket]) => [key, summarize(bucket)]),
      ),
    },
    null,
    2,
  ),
);
