# Certificate Management Improvements

**Status**: Proposed
**Created**: 2026-02-04
**Author**: Claude
**Priority**: High (Phase 1), Medium (Phase 2-3)

## Problem Statement

Currently, users must manually export and upload iOS certificates for every build. This creates friction and doesn't leverage the infrastructure we've built for secure credential delivery.

**Current pain points:**
1. Manual certificate export required per build
2. No certificate reuse across builds
3. All builds require certificates (even for testing)
4. Users must manage certificate expiration manually

## Goals

1. **Reduce friction**: Store and reuse certificates across builds
2. **Improve security**: Encrypted credential storage
3. **Add flexibility**: Support simulator builds (no certs needed)
4. **Optional automation**: Integrate with Fastlane Match for teams

## Three-Phase Approach

### Phase 1: Certificate Reuse ⭐ (Quick Win)
**Time**: 4-6 hours
**Value**: High
**Risk**: Low

Store uploaded certificates securely, reuse for future builds of the same bundle ID.

### Phase 2: Fastlane Match Integration (Optional)
**Time**: 1 week
**Value**: High for teams
**Risk**: Medium (external dependency)

Auto-fetch certificates from git repository using Fastlane Match.

### Phase 3: Simulator Builds (Testing)
**Time**: 6-8 hours
**Value**: Medium
**Risk**: Low

Support unsigned simulator builds for quick validation.

---

## Phase 1: Certificate Reuse (RECOMMENDED START)

### Overview

After first certificate upload, store encrypted credentials in database. Reuse for future builds until expiration.

### User Flow

```
Build 1 (Bundle ID: com.example.app):
  1. User uploads certs
  2. Build succeeds
  3. System: "Save these certificates for future builds?"
  4. User: "Yes" → Certs stored encrypted

Build 2 (Same Bundle ID):
  1. User submits build (no cert upload)
  2. System: "Using saved certificates (expires 2026-08-15)"
  3. Build succeeds

Build 3 (Different Bundle ID):
  1. User uploads new certs (different bundle ID)
  2. Process repeats
```

### Database Schema

**New table: `credentials`**

```sql
-- packages/controller-elixir/priv/repo/migrations/YYYYMMDDHHMMSS_create_credentials.exs
defmodule ExpoController.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bundle_id, :string, null: false
      add :team_id, :string, null: false
      add :encrypted_data, :binary, null: false
      add :certificate_type, :string, null: false  # "distribution", "development", "adhoc"
      add :expires_at, :utc_datetime, null: false
      add :created_by_user_id, :string  # Future: link to user accounts

      timestamps()
    end

    create unique_index(:credentials, [:bundle_id, :team_id, :certificate_type])
    create index(:credentials, [:expires_at])
    create index(:credentials, [:bundle_id])
  end
end
```

### Implementation Files

#### 1. Credential Schema
**File**: `packages/controller-elixir/lib/expo_controller/credentials/credential.ex`

```elixir
defmodule ExpoController.Credentials.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "credentials" do
    field :bundle_id, :string
    field :team_id, :string
    field :encrypted_data, :binary
    field :certificate_type, :string
    field :expires_at, :utc_datetime
    field :created_by_user_id, :string

    timestamps()
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:bundle_id, :team_id, :encrypted_data, :certificate_type, :expires_at])
    |> validate_required([:bundle_id, :team_id, :encrypted_data, :certificate_type, :expires_at])
    |> validate_inclusion(:certificate_type, ["distribution", "development", "adhoc"])
    |> unique_constraint([:bundle_id, :team_id, :certificate_type])
  end
end
```

#### 2. Credentials Context
**File**: `packages/controller-elixir/lib/expo_controller/credentials.ex`

```elixir
defmodule ExpoController.Credentials do
  import Ecto.Query
  alias ExpoController.Repo
  alias ExpoController.Credentials.Credential

  @doc """
  Save credentials for future reuse

  cert_data format:
  %{
    "p12" => "base64...",
    "p12Password" => "pass",
    "keychainPassword" => "kc-pass",
    "provisioningProfiles" => ["base64...", ...]
  }
  """
  def save_credentials(bundle_id, team_id, cert_data, certificate_type \\ "distribution") do
    # 1. Extract expiration from provisioning profile
    expires_at = extract_expiration_date(cert_data)

    # 2. Encrypt data using Cloak
    encrypted = encrypt_credential_data(cert_data)

    # 3. Upsert credential
    %Credential{}
    |> Credential.changeset(%{
      bundle_id: bundle_id,
      team_id: team_id,
      encrypted_data: encrypted,
      certificate_type: certificate_type,
      expires_at: expires_at
    })
    |> Repo.insert(
      on_conflict: {:replace, [:encrypted_data, :expires_at, :updated_at]},
      conflict_target: [:bundle_id, :team_id, :certificate_type]
    )
  end

  @doc """
  Get stored credentials for bundle ID + team
  Returns {:ok, cert_data} or {:error, reason}
  """
  def get_credentials(bundle_id, team_id, certificate_type \\ "distribution") do
    Credential
    |> where(bundle_id: ^bundle_id, team_id: ^team_id, certificate_type: ^certificate_type)
    |> where([c], c.expires_at > ^DateTime.utc_now())
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}
      credential ->
        decrypted = decrypt_credential_data(credential.encrypted_data)
        {:ok, decrypted, credential.expires_at}
    end
  end

  @doc """
  Delete expired credentials (run via periodic job)
  """
  def delete_expired_credentials do
    Credential
    |> where([c], c.expires_at < ^DateTime.utc_now())
    |> Repo.delete_all()
  end

  # Private functions

  defp extract_expiration_date(cert_data) do
    # Decode first provisioning profile
    profile_b64 = List.first(cert_data["provisioningProfiles"] || [])

    if profile_b64 do
      profile_data = Base.decode64!(profile_b64)

      # Write to temp file
      temp_file = System.tmp_dir!() <> "/profile-#{:rand.uniform(999999)}.mobileprovision"
      File.write!(temp_file, profile_data)

      # Extract expiration using security command
      {output, 0} = System.cmd("security", [
        "cms", "-D", "-i", temp_file
      ])

      # Parse plist and extract ExpirationDate
      {plist_output, 0} = System.cmd("plutil", [
        "-extract", "ExpirationDate", "raw", "-"
      ], input: output)

      File.rm!(temp_file)

      # Parse date: "2026-08-15T12:00:00Z"
      {:ok, datetime, _} = DateTime.from_iso8601(String.trim(plist_output))
      datetime
    else
      # Default: 1 year from now
      DateTime.add(DateTime.utc_now(), 365 * 24 * 60 * 60, :second)
    end
  end

  defp encrypt_credential_data(cert_data) do
    # Use Cloak for encryption (install: cloak_ecto)
    json = Jason.encode!(cert_data)
    ExpoController.Vault.encrypt!(json)
  end

  defp decrypt_credential_data(encrypted_binary) do
    json = ExpoController.Vault.decrypt!(encrypted_binary)
    Jason.decode!(json)
  end
end
```

#### 3. Vault Configuration (Encryption)
**File**: `packages/controller-elixir/lib/expo_controller/vault.ex`

```elixir
defmodule ExpoController.Vault do
  use Cloak.Vault, otp_app: :expo_controller

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1",
          key: decode_env!("CREDENTIAL_ENCRYPTION_KEY"),
          iv_length: 12
        }
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
```

**Config**: `packages/controller-elixir/config/config.exs`

```elixir
config :expo_controller, ExpoController.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: :from_init}
  ]
```

**Environment variable** (generate once):
```bash
# Generate 32-byte key
openssl rand -base64 32
# Set in .env: CREDENTIAL_ENCRYPTION_KEY=<generated-key>
```

#### 4. Modified Build Controller
**File**: `packages/controller-elixir/lib/expo_controller_web/controllers/build_controller.ex`

```elixir
defmodule ExpoControllerWeb.BuildController do
  alias ExpoController.Credentials

  def create(conn, %{"platform" => "ios", "source" => source} = params) do
    # Extract bundle ID from source
    bundle_id = extract_bundle_id_from_source(source.path)
    team_id = extract_team_id_from_source(source.path)

    # Check for uploaded certs OR saved certs
    certs_result = case Map.get(params, "certs") do
      nil ->
        # No certs uploaded, try to fetch saved
        Credentials.get_credentials(bundle_id, team_id)

      certs_upload ->
        # Certs uploaded, use them
        cert_data = parse_uploaded_certs(certs_upload.path)

        # Optionally save for future (could add "save_credentials" param)
        if Map.get(params, "save_credentials", false) do
          Credentials.save_credentials(bundle_id, team_id, cert_data)
        end

        {:ok, cert_data, nil}
    end

    case certs_result do
      {:ok, cert_data, expires_at} ->
        # Continue with build using cert_data
        # ... existing build logic ...

        # Include expiration in response
        conn
        |> put_resp_header("x-certs-expires-at", to_string(expires_at))
        |> json(%{...})

      {:error, :not_found} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "No certificates provided and no saved credentials found",
          bundle_id: bundle_id,
          team_id: team_id
        })
    end
  end

  defp extract_bundle_id_from_source(source_path) do
    # Unzip source
    # Read app.json or Info.plist
    # Extract bundle ID
    # Implementation needed
  end

  defp extract_team_id_from_source(source_path) do
    # Extract from app.json ios.teamId or ios.appleTeamId
    # Implementation needed
  end

  defp parse_uploaded_certs(certs_zip_path) do
    # Existing logic to parse certs.zip
    # Return %{"p12" => "...", "p12Password" => "...", ...}
  end
end
```

#### 5. API Endpoint: List Saved Credentials
**File**: Add to `BuildController`

```elixir
def list_credentials(conn, %{"bundle_id" => bundle_id, "team_id" => team_id}) do
  case Credentials.get_credentials(bundle_id, team_id) do
    {:ok, _cert_data, expires_at} ->
      json(conn, %{
        bundle_id: bundle_id,
        team_id: team_id,
        expires_at: expires_at,
        days_until_expiration: DateTime.diff(expires_at, DateTime.utc_now(), :day)
      })

    {:error, :not_found} ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "No saved credentials found"})
  end
end

def delete_credentials(conn, %{"bundle_id" => bundle_id, "team_id" => team_id}) do
  # Delete saved credentials
  # Implementation needed
end
```

#### 6. Periodic Cleanup Job
**File**: `packages/controller-elixir/lib/expo_controller/credentials/cleanup_worker.ex`

```elixir
defmodule ExpoController.Credentials.CleanupWorker do
  use GenServer
  alias ExpoController.Credentials

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Run cleanup every 24 hours
    schedule_cleanup()
    {:ok, state}
  end

  def handle_info(:cleanup, state) do
    Credentials.delete_expired_credentials()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    # 24 hours in milliseconds
    Process.send_after(self(), :cleanup, 24 * 60 * 60 * 1000)
  end
end
```

Add to supervision tree in `application.ex`:
```elixir
children = [
  # ... existing children ...
  ExpoController.Credentials.CleanupWorker
]
```

### Dependencies

**Add to `mix.exs`:**
```elixir
defp deps do
  [
    # ... existing deps ...
    {:cloak_ecto, "~> 1.2"}
  ]
end
```

### Testing

**File**: `packages/controller-elixir/test/expo_controller/credentials_test.exs`

```elixir
defmodule ExpoController.CredentialsTest do
  use ExpoController.DataCase
  alias ExpoController.Credentials

  @valid_cert_data %{
    "p12" => Base.encode64("fake-p12-data"),
    "p12Password" => "password",
    "keychainPassword" => "kc-password",
    "provisioningProfiles" => [Base.encode64("fake-profile")]
  }

  test "saves and retrieves credentials" do
    bundle_id = "com.test.app"
    team_id = "ABC123"

    assert {:ok, credential} = Credentials.save_credentials(
      bundle_id,
      team_id,
      @valid_cert_data
    )

    assert {:ok, cert_data, expires_at} = Credentials.get_credentials(bundle_id, team_id)
    assert cert_data["p12"] == @valid_cert_data["p12"]
    assert expires_at != nil
  end

  test "returns error for non-existent credentials" do
    assert {:error, :not_found} = Credentials.get_credentials("com.missing.app", "XYZ789")
  end

  test "does not return expired credentials" do
    bundle_id = "com.expired.app"
    team_id = "ABC123"

    # Save with past expiration
    past_date = DateTime.add(DateTime.utc_now(), -1, :day)

    # Manual insert with past expiration
    %Credential{
      bundle_id: bundle_id,
      team_id: team_id,
      encrypted_data: encrypt_data(@valid_cert_data),
      certificate_type: "distribution",
      expires_at: past_date
    }
    |> Repo.insert!()

    assert {:error, :not_found} = Credentials.get_credentials(bundle_id, team_id)
  end
end
```

### Acceptance Criteria

- [ ] User uploads certs for build → option to save credentials
- [ ] Saved credentials stored encrypted in database
- [ ] Future builds can use saved certs (no upload required)
- [ ] Expired credentials not returned (auto-filtered)
- [ ] Cleanup job removes expired credentials daily
- [ ] API endpoints to list/delete saved credentials
- [ ] Tests for save/retrieve/expiration logic
- [ ] Documentation for users on credential reuse

### CLI Changes (Optional)

Update `packages/cli/src/commands/submit.ts` to support credential reuse:

```typescript
// Check if saved credentials exist
const checkResponse = await fetch(
  `${controllerUrl}/api/credentials?bundle_id=${bundleId}&team_id=${teamId}`
);

if (checkResponse.ok) {
  const { expires_at } = await checkResponse.json();
  console.log(`✓ Using saved certificates (expires ${expires_at})`);

  // Submit without certs
  formData.append('use_saved_credentials', 'true');
} else {
  // Need to upload certs
  console.log('ℹ No saved credentials found, uploading certificates...');
  const certsZip = await findCertificates();
  formData.append('certs', certsZip);
  formData.append('save_credentials', 'true');  // Save for future
}
```

---

## Phase 2: Fastlane Match Integration (OPTIONAL)

### Overview

Integrate with Fastlane Match to auto-fetch certificates from a git repository.

### User Flow

```
Setup (One-time):
  1. User runs: fastlane match init
  2. Creates git repo for certs
  3. Runs: fastlane match appstore
  4. Certs stored in git (encrypted)

Build via expo-free-agent:
  1. User provides Match config (git URL, credentials)
  2. expo-free-agent runs: fastlane match appstore --readonly
  3. Certs auto-downloaded from git
  4. Build proceeds
```

### Implementation

**File**: `packages/controller-elixir/lib/expo_controller/apple/fastlane_match.ex`

```elixir
defmodule ExpoController.Apple.FastlaneMatch do
  @doc """
  Fetch certificates using Fastlane Match

  match_config:
  %{
    "git_url" => "git@github.com:org/certs.git",
    "git_token" => "ghp_...",
    "encryption_password" => "match-password",
    "apple_id" => "dev@company.com",
    "team_id" => "ABC123"
  }
  """
  def fetch_certificates(bundle_id, match_config, type \\ "appstore") do
    # 1. Create temp directory
    temp_dir = create_temp_match_dir()

    # 2. Write Matchfile
    write_matchfile(temp_dir, bundle_id, match_config, type)

    # 3. Set environment variables
    env = build_env_vars(match_config)

    # 4. Run fastlane match
    case run_fastlane_match(temp_dir, type, env) do
      {:ok, output} ->
        # 5. Extract certificate paths
        cert_info = extract_cert_info_from_match_output(output)

        # 6. Read certificates into memory
        cert_data = read_certificates(cert_info)

        # 7. Cleanup
        File.rm_rf!(temp_dir)

        {:ok, cert_data}

      {:error, reason} ->
        File.rm_rf!(temp_dir)
        {:error, reason}
    end
  end

  defp create_temp_match_dir do
    dir = System.tmp_dir!() <> "/match-#{:rand.uniform(999999)}"
    File.mkdir_p!(dir)
    dir
  end

  defp write_matchfile(dir, bundle_id, config, type) do
    matchfile = """
    git_url("#{config["git_url"]}")
    storage_mode("git")
    type("#{type}")
    app_identifier("#{bundle_id}")
    team_id("#{config["team_id"]}")
    readonly(true)
    """

    File.write!("#{dir}/Matchfile", matchfile)
  end

  defp build_env_vars(config) do
    %{
      "MATCH_PASSWORD" => config["encryption_password"],
      "GIT_URL" => config["git_url"],
      "GIT_TOKEN" => config["git_token"]
    }
  end

  defp run_fastlane_match(dir, type, env) do
    case System.cmd("fastlane", ["match", type, "--readonly"],
      cd: dir,
      env: env,
      stderr_to_stdout: true
    ) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "Fastlane match failed (code #{code}): #{output}"}
    end
  end

  defp extract_cert_info_from_match_output(output) do
    # Parse fastlane output to find:
    # - P12 path
    # - Provisioning profile paths
    # - Keychain password
    # Example output parsing needed
  end

  defp read_certificates(cert_info) do
    # Read P12 and profiles from filesystem
    # Convert to base64
    # Return in standard format
    %{
      "p12" => Base.encode64(File.read!(cert_info.p12_path)),
      "p12Password" => cert_info.p12_password,
      "keychainPassword" => generate_keychain_password(),
      "provisioningProfiles" =>
        Enum.map(cert_info.profile_paths, fn path ->
          Base.encode64(File.read!(path))
        end)
    }
  end

  defp generate_keychain_password do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end
end
```

**Modified Build Controller:**

```elixir
def create(conn, %{"platform" => "ios", "source" => source, "match_config" => match_config}) do
  bundle_id = extract_bundle_id_from_source(source.path)

  # Fetch certs using Match
  case Apple.FastlaneMatch.fetch_certificates(bundle_id, match_config) do
    {:ok, cert_data} ->
      # Continue with build
      # ... existing logic ...

    {:error, reason} ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Failed to fetch certificates via Match: #{reason}"})
  end
end
```

### Dependencies

- Fastlane installed on controller host
- Git access to certificate repository
- Bundler (for Fastlane)

```dockerfile
# If running in Docker
RUN gem install fastlane
```

### Acceptance Criteria

- [ ] Controller can run Fastlane Match
- [ ] Certificates fetched from git repository
- [ ] Match config validated before execution
- [ ] Errors from Match properly surfaced to user
- [ ] Certs from Match used in build
- [ ] Documentation for setting up Match

---

## Phase 3: Simulator Builds (TESTING)

### Overview

Support unsigned builds for iOS Simulator (no certificates required).

### User Flow

```
Submit Simulator Build:
  1. User: expo build --platform ios --target simulator
  2. No certificates required
  3. Build produces .app bundle
  4. User downloads and runs: xcrun simctl install booted App.app

Submit Device Build:
  1. User: expo build --platform ios --target device
  2. Certificates required (use saved or upload)
  3. Build produces signed .ipa
```

### API Changes

**Modified submit endpoint:**

```elixir
def create(conn, %{"platform" => "ios", "target" => target, "source" => source} = params)
  when target in ["simulator", "device", "appstore"] do

  case target do
    "simulator" ->
      # No certs needed
      create_simulator_build(conn, source)

    "device" ->
      # Certs required
      create_device_build(conn, source, params)

    "appstore" ->
      # Certs required
      create_appstore_build(conn, source, params)
  end
end

defp create_simulator_build(conn, source) do
  # Create build without certs
  build = %Build{
    platform: :ios,
    target: :simulator,
    source_path: save_source(source),
    certs_path: nil,  # No certs
    status: :pending
  }
  |> Repo.insert!()

  # Enqueue build
  QueueManager.enqueue_build(build)

  json(conn, %{id: build.id, target: "simulator"})
end
```

### Bootstrap Script Changes

**File**: `free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh`

```bash
#!/bin/bash

# ... existing setup ...

# Read build config
BUILD_TARGET=$(jq -r '.target // "device"' /tmp/build-config.json)

if [[ "$BUILD_TARGET" == "simulator" ]]; then
    log "Building for iOS Simulator (no code signing)"

    # Build for simulator
    xcodebuild \
      -project ./ios/*.xcodeproj \
      -scheme "$SCHEME" \
      -sdk iphonesimulator \
      -configuration Debug \
      -derivedDataPath ./build \
      build

    # Package .app bundle
    APP_PATH=$(find ./build/Build/Products/Debug-iphonesimulator -name "*.app" -type d | head -1)
    cd "$(dirname "$APP_PATH")"
    zip -r /tmp/app-simulator.zip "$(basename "$APP_PATH")"

    # Upload artifact
    upload_artifact "/tmp/app-simulator.zip"

else
    log "Building for device (code signing required)"

    # Download and install certificates
    # ... existing certificate installation logic ...

    # Build for device
    xcodebuild \
      -project ./ios/*.xcodeproj \
      -scheme "$SCHEME" \
      -configuration Release \
      -archivePath /tmp/app.xcarchive \
      archive

    # Export IPA
    # ... existing export logic ...
fi
```

### Acceptance Criteria

- [ ] Simulator builds complete without certificates
- [ ] Simulator builds produce .app bundle
- [ ] Device builds still require certificates
- [ ] CLI supports --target simulator flag
- [ ] Documentation for simulator builds
- [ ] Build logs clearly indicate simulator vs device build

---

## Implementation Order

### Week 1: Phase 1 (Certificate Reuse)
- Day 1-2: Database schema, Vault setup, Credentials context
- Day 3: Controller changes (save/retrieve certs)
- Day 4: Testing, cleanup job
- Day 5: CLI changes, documentation

### Week 2: Phase 3 (Simulator Builds) - Optional
- Day 1-2: Bootstrap script changes
- Day 3: Controller API changes
- Day 4-5: Testing, CLI support

### Week 3-4: Phase 2 (Fastlane Match) - Optional
- Week 3: Fastlane integration, testing
- Week 4: Documentation, edge cases, polish

## Risk Mitigation

1. **Encryption key management**
   - Generate strong key once
   - Store in environment variable
   - Document key rotation procedure
   - Consider key management service (Vault, AWS KMS)

2. **Certificate expiration**
   - Daily cleanup job
   - Warning emails before expiration (future)
   - Grace period before hard failure

3. **Fastlane dependency**
   - Make optional (Phase 2)
   - Document version requirements
   - Test across Fastlane versions

4. **Data migration**
   - No breaking changes to existing builds
   - Credentials opt-in (not required)
   - Backwards compatible API

## Success Metrics

- **Adoption**: % of builds using saved credentials (target: 70% after 1 month)
- **Friction reduction**: Time from "run build" to "build starts" (target: < 30s)
- **Security**: Zero credential leaks (audit encryption, access logs)
- **Reliability**: Credential retrieval success rate (target: 99.9%)

## Future Enhancements

1. **User accounts**: Link credentials to users, team sharing
2. **Certificate renewal alerts**: Email 30/14/7 days before expiration
3. **Multiple certificates per bundle ID**: Development, distribution, adhoc
4. **Credential versioning**: Keep history of certificates
5. **App Store Connect API**: Full automation (Phase 4)
6. **Certificate health dashboard**: UI showing all saved certs, expiration status

## Questions to Resolve

- **User authentication**: How to authenticate users for credential management?
- **Team sharing**: How to share credentials across team members?
- **Audit logging**: Track who accessed/modified credentials?
- **Key rotation**: How to rotate encryption key without losing credentials?

## Documentation Needed

1. **User guide**: How to save and reuse certificates
2. **Setup guide**: Encryption key generation, environment setup
3. **Fastlane Match guide**: How to set up Match with expo-free-agent
4. **API docs**: New credential endpoints
5. **Security guide**: Encryption, key management, best practices
