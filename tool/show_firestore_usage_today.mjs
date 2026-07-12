const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const configPath = `${process.env.USERPROFILE}\\.config\\configstore\\firebase-tools.json`;

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

async function sumMetric(metricType, startTime, endTime) {
  const params = new URLSearchParams({
    filter: `metric.type="${metricType}"`,
    'interval.startTime': startTime,
    'interval.endTime': endTime,
    'aggregation.alignmentPeriod': '60s',
    'aggregation.perSeriesAligner': 'ALIGN_SUM',
    'aggregation.crossSeriesReducer': 'REDUCE_SUM',
  });
  const url = `https://monitoring.googleapis.com/v3/projects/${projectId}/timeSeries?${params}`;
  const json = await api(url);
  let total = 0;
  for (const series of json.timeSeries || []) {
    for (const point of series.points || []) {
      const value = point.value || {};
      const raw = value.int64Value ?? value.doubleValue ?? 0;
      total += Number(raw);
    }
  }
  return total;
}

function isoNow() {
  return new Date().toISOString();
}

function startOfPakistanToday(now = new Date()) {
  const pk = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Karachi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
    .format(now)
    .replaceAll('/', '-');
  return new Date(`${pk}T00:00:00+05:00`).toISOString();
}

function startOfPacificToday(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Los_Angeles',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
    .format(now)
    .replaceAll('/', '-');
  return new Date(`${parts}T00:00:00-07:00`).toISOString();
}

const metrics = {
  reads: 'firestore.googleapis.com/document/read_count',
  writes: 'firestore.googleapis.com/document/write_count',
};

const end = isoNow();
const windows = {
  pakistanToday: {
    label: 'Today since 00:00 Asia/Karachi',
    start: startOfPakistanToday(),
  },
  firebaseQuotaDay: {
    label: 'Firebase quota day since 00:00 Pacific',
    start: startOfPacificToday(),
  },
};

const output = { projectId, end, windows: {} };
for (const [key, win] of Object.entries(windows)) {
  output.windows[key] = {
    label: win.label,
    start: win.start,
    end,
    reads: Math.round(await sumMetric(metrics.reads, win.start, end)),
    writes: Math.round(await sumMetric(metrics.writes, win.start, end)),
  };
}
console.log(JSON.stringify(output, null, 2));
