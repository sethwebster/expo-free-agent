import { nanoid } from 'nanoid';

export interface DemoWorker {
  id: string;
  name: string;
  status: 'idle' | 'building' | 'offline';
  capabilities: string;
  builds_completed: number;
  builds_failed: number;
  registered_at: number;
  last_seen_at: number;
}

export interface DemoBuild {
  id: string;
  status: 'pending' | 'assigned' | 'building' | 'completed' | 'failed';
  platform: 'ios' | 'android';
  worker_id: string | null;
  worker_name: string | null;
  submitted_at: number;
  started_at: number | null;
  completed_at: number | null;
  source_path: string;
  certs_path: string | null;
  result_path: string | null;
  error_message: string | null;
}

export interface DemoData {
  builds: DemoBuild[];
  workers: DemoWorker[];
  stats: {
    totalBuilds: number;
    pendingBuilds: number;
    activeBuilds: number;
    totalWorkers: number;
  };
  chartData: {
    buildsOverTime: Array<{ date: string; ios: number; android: number }>;
    successRate: Array<{ hour: number; success: number; failed: number }>;
    workerUtilization: Array<{ worker: string; completed: number; failed: number }>;
    buildDurations: Array<{ platform: string; avgDuration: number; minDuration: number; maxDuration: number }>;
    platformDistribution: { ios: number; android: number };
    statusDistribution: { completed: number; failed: number; building: number; pending: number };
  };
}

const workerNames = [
  'builder-prod-01',
  'builder-prod-02',
  'builder-staging-01',
  'worker-us-east-1a',
  'worker-us-west-2b',
  'ios-builder-01',
  'android-builder-01',
  'hybrid-builder-01',
];

const platforms: Array<'ios' | 'android'> = ['ios', 'android'];

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomChoice<T>(arr: T[]): T {
  return arr[randomInt(0, arr.length - 1)];
}

export function generateDemoData(): DemoData {
  const now = Date.now();
  const oneDayAgo = now - 24 * 60 * 60 * 1000;
  const oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000;

  // Generate workers
  const workers: DemoWorker[] = workerNames.map((name, i) => {
    const completed = randomInt(50, 500);
    const failed = randomInt(5, 50);
    const isOffline = i >= 6; // Last 2 workers offline

    return {
      id: nanoid(),
      name,
      status: isOffline ? 'offline' : i === 0 ? 'building' : 'idle',
      capabilities: JSON.stringify({
        platforms: name.includes('ios-')
          ? ['ios']
          : name.includes('android-')
          ? ['android']
          : ['ios', 'android'],
      }),
      builds_completed: completed,
      builds_failed: failed,
      registered_at: oneWeekAgo + randomInt(0, 6 * 24 * 60 * 60 * 1000),
      last_seen_at: isOffline ? now - randomInt(2, 6) * 60 * 60 * 1000 : now - randomInt(1, 300) * 1000,
    };
  });

  // Generate builds with realistic distribution
  const builds: DemoBuild[] = [];
  const totalBuilds = 150;

  for (let i = 0; i < totalBuilds; i++) {
    const platform = randomChoice(platforms);
    const submittedAt = oneDayAgo + randomInt(0, 24 * 60 * 60 * 1000);

    // Determine status based on recency and randomness
    let status: DemoBuild['status'];
    const rand = Math.random();
    const recency = (now - submittedAt) / (24 * 60 * 60 * 1000);

    if (recency < 0.05) {
      // Recent builds - might be pending/building
      if (rand < 0.3) status = 'pending';
      else if (rand < 0.5) status = 'building';
      else if (rand < 0.85) status = 'completed';
      else status = 'failed';
    } else {
      // Older builds - mostly completed or failed
      if (rand < 0.85) status = 'completed';
      else status = 'failed';
    }

    const worker = status !== 'pending' ? randomChoice(workers.filter(w => w.status !== 'offline')) : null;
    const startedAt = status !== 'pending' ? submittedAt + randomInt(5000, 60000) : null;

    // Build duration: iOS typically longer (4-8 min), Android (2-5 min)
    const baseDuration = platform === 'ios' ? randomInt(240, 480) : randomInt(120, 300);
    const duration = baseDuration * 1000;

    const completedAt =
      status === 'completed' || status === 'failed'
        ? startedAt! + duration
        : null;

    builds.push({
      id: nanoid(),
      status,
      platform,
      worker_id: worker?.id || null,
      worker_name: worker?.name || null,
      submitted_at: submittedAt,
      started_at: startedAt,
      completed_at: completedAt,
      source_path: `/storage/source/${nanoid()}.zip`,
      certs_path: platform === 'ios' ? `/storage/certs/${nanoid()}.zip` : null,
      result_path: status === 'completed' ? `/storage/result/${nanoid()}.${platform === 'ios' ? 'ipa' : 'apk'}` : null,
      error_message: status === 'failed' ? randomChoice([
        'Xcode build failed: Code signing error',
        'Gradle build failed: Missing dependency',
        'Build timeout after 10 minutes',
        'Certificate expired',
        'Network error during dependency download',
      ]) : null,
    });
  }

  // Sort builds by submitted_at descending
  builds.sort((a, b) => b.submitted_at - a.submitted_at);

  // Calculate stats
  const pendingBuilds = builds.filter(b => b.status === 'pending').length;
  const activeBuilds = builds.filter(b => b.status === 'assigned' || b.status === 'building').length;

  // Generate chart data
  const buildsOverTime: Array<{ date: string; ios: number; android: number }> = [];
  for (let i = 6; i >= 0; i--) {
    const date = new Date(now - i * 24 * 60 * 60 * 1000);
    const dayStart = date.setHours(0, 0, 0, 0);
    const dayEnd = date.setHours(23, 59, 59, 999);

    const dayBuilds = builds.filter(b => b.submitted_at >= dayStart && b.submitted_at <= dayEnd);

    buildsOverTime.push({
      date: new Date(dayStart).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      ios: dayBuilds.filter(b => b.platform === 'ios').length,
      android: dayBuilds.filter(b => b.platform === 'android').length,
    });
  }

  // Success rate by hour (last 24 hours)
  const successRate: Array<{ hour: number; success: number; failed: number }> = [];
  for (let hour = 0; hour < 24; hour++) {
    const hourStart = oneDayAgo + hour * 60 * 60 * 1000;
    const hourEnd = hourStart + 60 * 60 * 1000;

    const hourBuilds = builds.filter(
      b => b.submitted_at >= hourStart && b.submitted_at < hourEnd
    );

    successRate.push({
      hour,
      success: hourBuilds.filter(b => b.status === 'completed').length,
      failed: hourBuilds.filter(b => b.status === 'failed').length,
    });
  }

  // Worker utilization
  const workerUtilization = workers
    .filter(w => w.status !== 'offline')
    .map(w => ({
      worker: w.name,
      completed: w.builds_completed,
      failed: w.builds_failed,
    }))
    .sort((a, b) => (b.completed + b.failed) - (a.completed + a.failed));

  // Build durations by platform
  const iosBuilds = builds.filter(b => b.platform === 'ios' && b.started_at && b.completed_at);
  const androidBuilds = builds.filter(b => b.platform === 'android' && b.started_at && b.completed_at);

  const iosDurations = iosBuilds.map(b => (b.completed_at! - b.started_at!) / 1000);
  const androidDurations = androidBuilds.map(b => (b.completed_at! - b.started_at!) / 1000);

  const buildDurations = [
    {
      platform: 'iOS',
      avgDuration: iosDurations.length ? Math.round(iosDurations.reduce((a, b) => a + b, 0) / iosDurations.length) : 0,
      minDuration: iosDurations.length ? Math.round(Math.min(...iosDurations)) : 0,
      maxDuration: iosDurations.length ? Math.round(Math.max(...iosDurations)) : 0,
    },
    {
      platform: 'Android',
      avgDuration: androidDurations.length ? Math.round(androidDurations.reduce((a, b) => a + b, 0) / androidDurations.length) : 0,
      minDuration: androidDurations.length ? Math.round(Math.min(...androidDurations)) : 0,
      maxDuration: androidDurations.length ? Math.round(Math.max(...androidDurations)) : 0,
    },
  ];

  // Platform distribution
  const platformDistribution = {
    ios: builds.filter(b => b.platform === 'ios').length,
    android: builds.filter(b => b.platform === 'android').length,
  };

  // Status distribution
  const statusDistribution = {
    completed: builds.filter(b => b.status === 'completed').length,
    failed: builds.filter(b => b.status === 'failed').length,
    building: builds.filter(b => b.status === 'building' || b.status === 'assigned').length,
    pending: builds.filter(b => b.status === 'pending').length,
  };

  return {
    builds: builds.slice(0, 50), // Only show last 50 on UI
    workers,
    stats: {
      totalBuilds: builds.length,
      pendingBuilds,
      activeBuilds,
      totalWorkers: workers.length,
    },
    chartData: {
      buildsOverTime,
      successRate,
      workerUtilization,
      buildDurations,
      platformDistribution,
      statusDistribution,
    },
  };
}
