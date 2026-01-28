# CPU Snapshot Implementation Guide

## Overview
This document describes how to implement CPU snapshot collection in the worker to track detailed resource usage during builds.

## Architecture

### Database Schema
CPU snapshots are stored in the `cpu_snapshots` table:
```sql
CREATE TABLE IF NOT EXISTS cpu_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  build_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  cpu_percent REAL NOT NULL, -- 0-100% CPU usage
  memory_mb REAL NOT NULL, -- Memory usage in MB
  FOREIGN KEY (build_id) REFERENCES builds(id)
);
```

### Controller API
The controller provides:
- `POST /builds/:id/telemetry` - Accepts telemetry data including CPU snapshots
- `GET /api/stats` - Returns aggregated stats including total build time and CPU cycles

### Stats Calculation
The controller calculates:
- **Total Build Time**: Sum of (completed_at - started_at) for all completed/failed builds
- **Total CPU Cycles**: Average CPU% × Total build time in seconds

## Worker Implementation

### Requirements
Workers should:
1. Collect CPU and memory usage every 5 seconds during builds
2. Send snapshots to controller via telemetry endpoint
3. Include accurate timestamps for each snapshot

### Example Swift Implementation (for FreeAgent.app)

```swift
// In your VM monitor or build executor:

func startCpuMonitoring(buildId: String) {
    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
        let cpuPercent = getCurrentCpuUsage() // 0-100
        let memoryMB = getCurrentMemoryUsage() // in MB

        sendTelemetry(
            buildId: buildId,
            type: "cpu_snapshot",
            data: [
                "cpu_percent": cpuPercent,
                "memory_mb": memoryMB
            ]
        )
    }
}

func sendTelemetry(buildId: String, type: String, data: [String: Any]) {
    let url = URL(string: "\(controllerUrl)/api/builds/\(buildId)/telemetry")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(workerId, forHTTPHeaderField: "X-Worker-Id")
    request.setValue(buildId, forHTTPHeaderField: "X-Build-Id")

    let body: [String: Any] = [
        "type": type,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "data": data
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request).resume()
}
```

### Testing CPU Snapshots

1. Submit a build:
```bash
bun cli submit ios path/to/app.zip
```

2. Monitor telemetry in controller logs:
```bash
tail -f controller.log | grep cpu_snapshot
```

3. Query CPU snapshots for a build:
```sql
SELECT * FROM cpu_snapshots WHERE build_id = 'build-xxx' ORDER BY timestamp;
```

4. Verify stats endpoint includes totals:
```bash
curl http://localhost:3000/api/stats | jq '.totalBuildTimeMs, .totalCpuCycles'
```

## Frontend Display

The landing page shows these metrics in the "Power in numbers" section:
- Total Time Building: Formatted as years/days/hours/minutes
- Total CPU Cycles: Formatted as billions/millions/thousands

Format examples:
- `24,008,176,200,000 ms` → `2y 280d`
- `9,603,270,480 cycles` → `9.60B`

## Migration Notes

The database schema is automatically created by the controller on startup via `schema.sql`.

For existing databases, the new `cpu_snapshots` table will be created automatically when the controller starts.

## Performance Considerations

- Snapshots are collected every 5 seconds (12 per minute)
- For a 5-minute build: 60 snapshots (~1KB of data)
- For 1 million builds: ~60 million snapshots (~60GB)
- Consider adding a cleanup job to archive old snapshots after 90 days

## Future Enhancements

1. **Per-build CPU graphs**: Display CPU usage over time for each build
2. **Anomaly detection**: Alert when CPU usage is abnormally high/low
3. **Worker performance comparison**: Compare CPU efficiency across different workers
4. **Cost calculation**: Estimate compute costs based on CPU cycles
