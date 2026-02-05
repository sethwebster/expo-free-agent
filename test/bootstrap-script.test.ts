import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const scriptPath = join(
  import.meta.dir,
  "..",
  "free-agent",
  "Sources",
  "WorkerCore",
  "Resources",
  "free-agent-bootstrap.sh"
);

const script = readFileSync(scriptPath, "utf8");

describe("free-agent-bootstrap.sh", () => {
  test("fails fast when jq is missing", () => {
    expect(script).toContain("jq not found in PATH");
  });

  test("captures xcodebuild output in build log", () => {
    expect(script).toContain("xcodebuild $BUILD_FLAG");
    expect(script).toContain("tee -a \"$BUILD_LOG\"");
  });

  test("logs provisioning profile parsing steps", () => {
    expect(script).toContain("Parsing provisioning profile");
    expect(script).toContain("security cms -D -i");
    expect(script).toContain("plutil -convert json");
  });
});
