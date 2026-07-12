const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const configPath = `${process.env.USERPROFILE}\\.config\\configstore\\firebase-tools.json`;
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

const fs = await import('node:fs/promises');
const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const accessToken = config?.tokens?.access_token;
if (!accessToken) {
  throw new Error('Firebase CLI access token was not found.');
}

async function api(url) {
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}: ${text}`);
  return JSON.parse(text);
}

function scalar(v) {
  if (!v || typeof v !== 'object') return undefined;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return String(v.integerValue);
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  return undefined;
}

async function list(path) {
  const docs = [];
  let pageToken = '';
  do {
    const params = new URLSearchParams({ pageSize: '300' });
    if (pageToken) params.set('pageToken', pageToken);
    const json = await api(`${base}/${path}?${params}`);
    docs.push(...(json.documents || []));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function docId(name) {
  return name.split('/').pop();
}

function memberKey(group) {
  return (group.members || [])
    .map((m) => String(m.rollNo || '').trim().toLowerCase())
    .filter(Boolean)
    .sort()
    .join('|');
}

function titleKey(group) {
  return String(group.title || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

const docs = await list('aust_portal_v2/data/cloud_fyp_groups');
const rows = [];
for (const doc of docs) {
  const fields = doc.fields || {};
  if (scalar(fields.deleted) === true) continue;
  const raw = scalar(fields.data);
  if (!raw) continue;
  try {
    const group = JSON.parse(raw);
    rows.push({
      cloudDocId: docId(doc.name),
      clientBuild: scalar(fields.client_build) || '',
      updatedAt: scalar(fields.updated_at) || group.updatedAt || '',
      group,
    });
  } catch {
    // Skip malformed legacy rows; the app also skips them.
  }
}

const byMembers = new Map();
const byTitle = new Map();
for (const row of rows) {
  const mk = memberKey(row.group);
  if (mk) (byMembers.get(mk) || byMembers.set(mk, []).get(mk)).push(row);
  const tk = titleKey(row.group);
  if (tk) (byTitle.get(tk) || byTitle.set(tk, []).get(tk)).push(row);
}

function summarize(label, map) {
  const duplicates = [...map.entries()]
    .filter(([, list]) => list.length > 1)
    .map(([key, list]) => ({
      key,
      count: list.length,
      groups: list.map(({ cloudDocId, clientBuild, updatedAt, group }) => ({
        cloudDocId,
        groupId: group.id,
        title: group.title,
        phase: group.phase,
        status: group.status,
        members: (group.members || []).map((m) => `${m.rollNo} ${m.name}`),
        clientBuild,
        updatedAt,
      })),
    }));
  return { label, duplicateSets: duplicates.length, duplicates };
}

console.log(
  JSON.stringify(
    {
      projectId,
      checkedAt: new Date().toISOString(),
      totalActiveGroups: rows.length,
      memberSetDuplicates: summarize('same members', byMembers),
      titleDuplicates: summarize('same title', byTitle),
    },
    null,
    2,
  ),
);
