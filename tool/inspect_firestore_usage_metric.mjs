const projectId = process.env.FIREBASE_PROJECT_ID || 'studentportal-36d0a';
const configPath = `${process.env.USERPROFILE}\\.config\\configstore\\firebase-tools.json`;

const fs = await import('node:fs/promises');
const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const accessToken = config?.tokens?.access_token;
if (!accessToken) throw new Error('Firebase CLI access token was not found.');

async function api(url) {
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}: ${text}`);
  return JSON.parse(text);
}

async function descriptor(metricType) {
  const params = new URLSearchParams({
    filter: `metric.type="${metricType}"`,
  });
  const url = `https://monitoring.googleapis.com/v3/projects/${projectId}/metricDescriptors?${params}`;
  const json = await api(url);
  return json.metricDescriptors?.[0] || {};
}

async function points(metricType, minutes) {
  const end = new Date();
  const start = new Date(end.getTime() - minutes * 60 * 1000);
  const params = new URLSearchParams({
    filter: `metric.type="${metricType}"`,
    'interval.startTime': start.toISOString(),
    'interval.endTime': end.toISOString(),
    'aggregation.alignmentPeriod': '60s',
    'aggregation.perSeriesAligner': 'ALIGN_SUM',
    'aggregation.crossSeriesReducer': 'REDUCE_SUM',
  });
  const url = `https://monitoring.googleapis.com/v3/projects/${projectId}/timeSeries?${params}`;
  return api(url);
}

for (const metricType of [
  'firestore.googleapis.com/document/read_count',
  'firestore.googleapis.com/document/write_count',
]) {
  const d = await descriptor(metricType);
  const p = await points(metricType, 60);
  const values = [];
  for (const series of p.timeSeries || []) {
    for (const point of series.points || []) {
      values.push({
        start: point.interval?.startTime,
        end: point.interval?.endTime,
        value: Number(point.value?.int64Value ?? point.value?.doubleValue ?? 0),
      });
    }
  }
  values.sort((a, b) => String(a.start).localeCompare(String(b.start)));
  console.log(
    JSON.stringify(
      {
        metricType,
        metricKind: d.metricKind,
        valueType: d.valueType,
        unit: d.unit,
        lastHourPointCount: values.length,
        lastHourTotal: values.reduce((sum, p) => sum + p.value, 0),
        firstPoint: values[0] || null,
        lastPoint: values[values.length - 1] || null,
      },
      null,
      2,
    ),
  );
}
