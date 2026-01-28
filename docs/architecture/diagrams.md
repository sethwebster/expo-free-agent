# Expo Free Agent - Architecture Diagrams

Visual representations of the system architecture, data flows, and component interactions.

## System Overview

```mermaid
graph TB
    subgraph "User Machine"
        CLI[Submit CLI<br/>Build submission]
    end

    subgraph "Controller (Central Server)"
        API[API Server<br/>Express + Bun]
        DB[(SQLite Database<br/>Jobs, Workers, State)]
        Storage[File Storage<br/>Source + Artifacts]
        Queue[Job Queue<br/>Assignment Logic]
    end

    subgraph "Worker Machine (Mac)"
        Worker[FreeAgent.app<br/>Menu Bar App]
        VM[macOS VM<br/>Isolated Build Environment]
    end

    CLI -->|1. Upload source<br/>HTTPS + API Key| API
    API -->|2. Store source| Storage
    API -->|3. Create job| DB
    DB -->|4. Queue job| Queue

    Worker -->|Poll for jobs| Queue
    Queue -->|5. Assign job| Worker
    Worker -->|6. Download source| Storage
    Worker -->|7. Execute build| VM
    VM -->|8. Build artifacts| Worker
    Worker -->|9. Upload artifacts| Storage
    Worker -->|10. Update status| DB

    CLI -->|11. Poll status| API
    API -->|12. Check status| DB
    CLI -->|13. Download artifacts| Storage

    style CLI fill:#4A90E2,stroke:#2E5C8A,color:#fff
    style API fill:#50C878,stroke:#2E7D4E,color:#fff
    style Worker fill:#9B59B6,stroke:#6C3483,color:#fff
    style VM fill:#E74C3C,stroke:#922B21,color:#fff
    style DB fill:#F39C12,stroke:#935116,color:#fff
    style Storage fill:#16A085,stroke:#0E6655,color:#fff
```

## Build Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant CLI
    participant Controller
    participant Database
    participant Worker
    participant VM

    User->>CLI: expo-build submit
    CLI->>CLI: Bundle source code
    CLI->>Controller: POST /builds (upload .tar.gz)
    Controller->>Database: INSERT build record
    Controller->>Database: INSERT job (status: pending)
    Controller-->>CLI: 201 Created {buildId, jobId}
    CLI-->>User: Build submitted: build-abc123

    Note over Worker,Database: Worker polls every 5 seconds
    Worker->>Controller: GET /jobs/next
    Controller->>Database: SELECT job WHERE status=pending
    Database-->>Controller: job-xyz789
    Controller->>Database: UPDATE job SET status=assigned
    Controller-->>Worker: 200 OK {job details}

    Worker->>Controller: GET /builds/{buildId}/source
    Controller-->>Worker: 200 OK (source.tar.gz)
    Worker->>VM: Create ephemeral VM
    Worker->>VM: Upload source
    VM->>VM: Extract and build
    VM->>VM: eas build --platform ios
    VM-->>Worker: Exit code 0, artifacts
    Worker->>Worker: Collect artifacts
    Worker->>Controller: POST /builds/{buildId}/artifacts
    Controller->>Database: UPDATE job SET status=completed
    Controller-->>Worker: 200 OK
    Worker->>VM: Destroy VM

    Note over CLI,Database: User polls for completion
    CLI->>Controller: GET /builds/{buildId}/status
    Controller->>Database: SELECT job status
    Database-->>Controller: status=completed
    Controller-->>CLI: 200 OK {status, artifacts}
    CLI->>Controller: GET /builds/{buildId}/artifacts/App.ipa
    Controller-->>CLI: 200 OK (binary stream)
    CLI-->>User: Download complete: App.ipa
```

## VM Isolation Model

```mermaid
graph TB
    subgraph "Worker Host (macOS)"
        HostOS[macOS Host OS]
        FreeAgent[FreeAgent.app<br/>Swift Application]
        HyperKit[Apple Virtualization<br/>Framework]

        subgraph "Security Boundaries"
            Firewall[Firewall Rules]
            FileSystem[Host Filesystem]
            Network[Host Network]
        end
    end

    subgraph "Isolated VM"
        GuestOS[macOS Guest OS<br/>Read-only System]
        BuildDir[/tmp/build-{id}<br/>Temporary Workspace]
        BuildProcess[eas build<br/>Untrusted Code]

        NetBlock[Network: BLOCKED<br/>No outbound access]
    end

    FreeAgent -->|Manages| HyperKit
    HyperKit -->|Hardware Isolation| GuestOS

    FreeAgent -.->|Copy source in| BuildDir
    FreeAgent -.->|Copy artifacts out| BuildDir

    BuildProcess -->|Read/Write| BuildDir
    BuildProcess -.->|Blocked| NetBlock
    BuildProcess -.->|Cannot access| FileSystem
    BuildProcess -.->|Cannot access| Network

    GuestOS -->|Ephemeral<br/>Destroyed after build| HyperKit

    style GuestOS fill:#E74C3C,stroke:#922B21,color:#fff
    style BuildProcess fill:#E67E22,stroke:#A04000,color:#fff
    style NetBlock fill:#95A5A6,stroke:#566573,color:#fff
    style HyperKit fill:#3498DB,stroke:#1A5490,color:#fff
    style FreeAgent fill:#9B59B6,stroke:#6C3483,color:#fff

    classDef blocked fill:#E74C3C,stroke:#922B21,stroke-dasharray: 5 5
    class NetBlock,FileSystem,Network blocked
```

## Component Interactions

### Build Submission Flow

```mermaid
graph LR
    A[User runs<br/>expo-build submit] --> B[CLI validates<br/>project]
    B --> C[CLI creates<br/>source tarball]
    C --> D[CLI uploads<br/>to controller]
    D --> E[Controller stores<br/>source]
    E --> F[Controller creates<br/>job record]
    F --> G[Job enters<br/>queue]

    style A fill:#4A90E2,color:#fff
    style G fill:#50C878,color:#fff
```

### Job Assignment Flow

```mermaid
graph LR
    A[Worker polls<br/>/jobs/next] --> B{Jobs available?}
    B -->|No| C[Wait 5s]
    C --> A
    B -->|Yes| D[Controller assigns<br/>job to worker]
    D --> E[Worker downloads<br/>source]
    E --> F[Worker creates VM]

    style A fill:#9B59B6,color:#fff
    style F fill:#E74C3C,color:#fff
```

### Build Execution Flow

```mermaid
graph TB
    A[VM Created] --> B[Source uploaded<br/>to /tmp/build-*]
    B --> C[Run: eas build]
    C --> D{Build success?}
    D -->|Yes| E[Collect artifacts]
    D -->|No| F[Collect logs]
    E --> G[Upload to controller]
    F --> G
    G --> H[Update job status]
    H --> I[Destroy VM]

    style A fill:#E74C3C,color:#fff
    style C fill:#E67E22,color:#fff
    style E fill:#50C878,color:#fff
    style F fill:#E74C3C,color:#fff
    style I fill:#95A5A6,color:#fff
```

### Artifact Download Flow

```mermaid
graph LR
    A[User runs<br/>expo-build download] --> B[CLI polls<br/>build status]
    B --> C{Complete?}
    C -->|No| D[Wait 10s]
    D --> B
    C -->|Yes| E[Request artifacts<br/>list]
    E --> F[Download each<br/>artifact]
    F --> G[Verify checksums]
    G --> H[Save to disk]

    style A fill:#4A90E2,color:#fff
    style H fill:#50C878,color:#fff
```

## Data Flow Visualization

### Source Code Journey

```mermaid
graph TB
    A[Local Project<br/>Directory] -->|tar + gzip| B[source.tar.gz<br/>~10-50 MB]
    B -->|HTTPS Upload| C[Controller Storage<br/>data/builds/{buildId}/source/]
    C -->|HTTPS Download| D[Worker<br/>Temporary Storage]
    D -->|VM Copy| E[VM Filesystem<br/>/tmp/build-{id}/]
    E -->|Build Process| F[Compiled Artifacts]
    F -->|VM Copy Out| G[Worker<br/>Temporary Storage]
    G -->|HTTPS Upload| H[Controller Storage<br/>data/builds/{buildId}/artifacts/]
    H -->|HTTPS Download| I[User Machine<br/>./App.ipa]

    style A fill:#4A90E2,color:#fff
    style E fill:#E74C3C,color:#fff
    style I fill:#50C878,color:#fff
```

### State Transitions

```mermaid
stateDiagram-v2
    [*] --> Pending: Job created
    Pending --> Assigned: Worker polls
    Assigned --> Running: VM started
    Running --> Completed: Build success
    Running --> Failed: Build error
    Running --> Timeout: Exceeded 30min
    Completed --> [*]
    Failed --> [*]
    Timeout --> [*]

    note right of Running
        Worker sends heartbeat
        every 30 seconds
    end note

    note right of Timeout
        Default: 30 minutes
        Configurable per project
    end note
```

## API Flow Diagrams

### Authentication Flow

```mermaid
sequenceDiagram
    participant Client
    participant Middleware
    participant Handler

    Client->>Middleware: Request + Authorization header
    Middleware->>Middleware: Extract API key
    Middleware->>Middleware: bcrypt.compare(key, hash)

    alt Valid API key
        Middleware->>Handler: Forward request
        Handler-->>Client: 200 Response
    else Invalid API key
        Middleware-->>Client: 401 Unauthorized
    end
```

### Upload Flow (Multipart)

```mermaid
sequenceDiagram
    participant CLI
    participant Controller
    participant Storage
    participant Database

    CLI->>Controller: POST /builds<br/>Content-Type: multipart/form-data
    Controller->>Controller: Validate API key
    Controller->>Controller: Parse multipart form
    Controller->>Controller: Generate buildId
    Controller->>Storage: Write source.tar.gz<br/>data/builds/{buildId}/source/
    Storage-->>Controller: Write complete
    Controller->>Database: INSERT build record
    Controller->>Database: INSERT job record
    Database-->>Controller: Success
    Controller-->>CLI: 201 Created<br/>{buildId, jobId}
```

### Download Flow (Streaming)

```mermaid
sequenceDiagram
    participant CLI
    participant Controller
    participant Storage
    participant Database

    CLI->>Controller: GET /builds/{buildId}/artifacts/App.ipa
    Controller->>Controller: Validate API key
    Controller->>Database: SELECT build WHERE id={buildId}
    Database-->>Controller: Build record

    alt Build not found
        Controller-->>CLI: 404 Not Found
    else Artifacts not ready
        Controller-->>CLI: 404 Not Found
    else Success
        Controller->>Storage: Stream file<br/>data/builds/{buildId}/artifacts/App.ipa
        Storage-->>CLI: 200 OK (stream chunks)
    end
```

## Information Hierarchy

```mermaid
graph TB
    Root[Documentation Root]

    Root --> GS[Getting Started]
    Root --> Arch[Architecture]
    Root --> Ops[Operations]
    Root --> Test[Testing]
    Root --> Comp[Components]

    GS --> QS[5-Minute Start]
    GS --> Local[Setup Local]
    GS --> Remote[Setup Remote]

    Arch --> Overview[System Overview]
    Arch --> Security[Security Model]
    Arch --> Diagrams[Diagrams]

    Ops --> Release[Release Process]
    Ops --> Notary[Notarization]
    Ops --> Gate[Gatekeeper]

    Test --> Testing[Test Strategies]
    Test --> Smoke[Smoketest]

    Comp --> Ctrl[Controller]
    Comp --> CLI[Submit CLI]
    Comp --> Worker[Worker App]

    style Root fill:#2C3E50,color:#fff
    style GS fill:#27AE60,color:#fff
    style Arch fill:#2980B9,color:#fff
    style Ops fill:#E67E22,color:#fff
    style Test fill:#8E44AD,color:#fff
    style Comp fill:#16A085,color:#fff
```

## Visual Style Guide

### Diagram Conventions

**Colors:**
- **User/CLI**: `#4A90E2` (Blue) - User-facing components
- **Controller**: `#50C878` (Green) - Server-side components
- **Worker**: `#9B59B6` (Purple) - Worker machine components
- **VM**: `#E74C3C` (Red) - Isolated build environment
- **Database**: `#F39C12` (Orange) - Persistent storage
- **File Storage**: `#16A085` (Teal) - File system storage
- **Error/Blocked**: `#E74C3C` (Red, dashed) - Security boundaries

**Shapes:**
- **Rectangles**: Services, processes, applications
- **Cylinders**: Databases, storage
- **Diamonds**: Decision points
- **Rounded boxes**: User interactions

**Line Styles:**
- **Solid arrows**: Data flow, API calls
- **Dashed arrows**: Blocked access, cannot access
- **Thick arrows**: Primary flow
- **Thin arrows**: Secondary flow

### Screenshot Standards

**Resolution:**
- Desktop: 2x retina (2880x1800 or similar)
- Scale down to 1440x900 for display
- Always use PNG format for clarity

**Annotations:**
- Use red arrows for "click here"
- Use yellow highlights for important areas
- Use numbered circles for step-by-step guides
- Add 2px border (#E0E0E0) around screenshots

**Context:**
- Always show enough context (full window when possible)
- Crop out personal information
- Use consistent theme (light mode preferred)

### Code Block Standards

**Filename headers:**
```bash
# filename: path/to/file.ts
code here...
```

**Line highlights:**
Use comments `// <--` for important lines

**Expected output:**
Always show output below commands:
```bash
$ expo-build submit
✓ Build submitted successfully
Build ID: build-abc123
```

---

**Navigation:**
- [Back to Architecture](./architecture.md)
- [Security Model](./security.md)
- [Documentation Index](../INDEX.md)
