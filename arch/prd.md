---
title: "PRD: Comn Framework"
create-date: 20251222
update-date: 
---

# Product Requirements Document

## Executive Summary

Comn is an Elixir umbrella application providing standardized, pluggable abstractions for common infrastructure functions. It eliminates boilerplate infrastructure code across distributed Elixir systems by providing semantic-first interfaces that work with multiple backend implementations.

## Product Goals

1. **Reduce Time-to-Market**: Cut infrastructure setup time by 50% through reusable abstractions.
2. **Enable Backend Flexibility**: Allow infrastructure changes without application logic refactoring.
3. **Standardize Developer Experience**: Create consistent patterns across all Comn-based projects.
4. **Support Distributed Systems**: Embrace OTP and BEAM's concurrency model natively.

## Functional Requirements

### 1. Errors Subsystem

**Purpose**: Provide standardized error handling, categorization, and reporting across all subsystems.

**Interfaces**:

- `Comn.Error.ErrorStruct` - Standard error representation with message, details, category, severity
- `Comn.Errors` - Behavior defining error handling modules
- `Comn.Error` - Protocol for converting any error to standard format
- `Comn.Error.Impl` - Implementations for specific error categories (validation, persistence, network, auth, internal)

**Requirements**:

- All errors must be convertible to `ErrorStruct`
- Errors must support categorization (validation, persistence, network, auth, internal)
- Errors must include stacktraces and context
- Error structs must be serializable to JSON
- Protocol must handle `Exception`, `Ecto.Changeset`, custom tuples

**Backend Providers**: None (pure module interface)

### 2. Events Subsystem

**Purpose**: Provide publish/subscribe abstraction with pluggable backends for domain and system events.

**Interfaces**:

- `Comn.Events.EventStruct` - Standard event struct (id, type, timestamp, metadata, payload, correlation_id)
- `Comn.EventBus` - Behaviour defining a local publish/subscribe bus
- `Comn.Events` - Behaviour defining the interface for event systems.
- `Comn.Event` - Protocol for event serialization/deserialization
- `Comn.EventLog` - In-memory, immutable event log that records and queries all activity.

**Backends**:

- Registry (local, in-memory) `Comn.EventBus`
- NATS (distributed, networked) `Comn.Events.NATS`
- OTEL (OpenTelemetry integration) `Comn.Events.OTel`

**Requirements**:

- Events must have correlation IDs for tracing
- Subscribers must support filtering by event type
- Publishers must be fire-and-forget (async)
- Backends must be hot-swappable via config
- Must support event versioning
- Event payloads must be schema-validated

**Non-Functional**:

- Latency: < 10ms for local backend
- Latency: < 300ms for networked backends
- Throughput: >= 10k events/sec per backend, able to scale horizontally without code changes or refactoring

### 3. Secrets Subsystem

**Purpose**: Unified management of credentials, tokens, API keys, and certificates with rotation support.

**Interfaces**:

- `Comn.Secret.SecretStore` - Behavior for secret storage/retrieval
- `Comn.Secret.Secret` - Standard secret struct (key, value, version, rotation_policy, expires_at)
- `Comn.Secret.Rotator` - Behavior for automated secret rotation

**Backends**:

- Environment variables (development)
- File-based (development/testing)
- Vault (HashiCorp Vault)
- AWS Secrets Manager
- Azure Key Vault

**Requirements**:

- Secrets must never be logged or printed
- Support rotation policies (manual, time-based, event-triggered)
- Track secret versions
- Support expiration with pre-expiry alerts
- Access must be audited
- Backends must be transparent to application code

**Non-Functional**:

- Latency: < 10ms for local backend
- Latency: < 300ms for networked backends
- Throughput: >= 10k events/sec per backend, able to scale horizontally without code changes or refactoring

### 4. Repo Subsystem

**Purpose**: Abstraction layer over diverse persistence backends with unified interface.

**Repo Types**:

- `Comn.Repo.Actor` - A behavior to handle Tasks, API calls, agent communication, etc.
- `Comn.Repo.Batch` - A behavior defining the interface for batch processing.
- `Comn.Repo.Blob` - A behavior defining the interface for blob storage systems.
- `Comn.Repo.Bus` - A behavior defining the interface for pub/sub message buses.
- `Comn.Repo.Cmd` - A behavior to handle command-line arguments and execute the appropriate functions.
- `Comn.Repo.Column` - A behavior defining the interface for columnar data stores.
- `Comn.Repo.File` - A behavior defining the interface for file repository operations.
- `Comn.Repo.Graph` - A behavior defining the interface for graph database operations and queries.
- `Comn.Repo.Merkel` - A behavior defining the interface for Merkle tree stores.
- `Comn.Repo.Queue` - A behavior defining the interface for durable message queues.
- `Comn.Repo.Stream` - A behavior defining the interface for stream processing systems.
- `Comn.Repo.Table` - A behavior defining the interface for relational databases.

**Unified Interface**:

- describe() - metadata about the repo
- get()
- set()
- delete()
- observe()

**Backends Per Type**:

- **Actor**: ETS, Mnesia, local memory
- **Batch**: HDFS, local filesystem
- **Blob**: S3, GCS, Azure Blob, local FS
- **Bus**: Redis, NATS, RabbitMQ
- **Cmd**: Postgres, EventStore, local file
- **Column**: ClickHouse, Apache Druid, Parquet
- **File**: Local FS, S3, GCS, Azure Blob
- **Graph**: Neo4j, Dgraph, ArangoDB
- **Merkel**: IPFS, local FS
- **Queue**: RabbitMQ, SQS, GCP Pub/Sub
- **Stream**: Kafka, Redis Streams, Pulsar
- **Table**: Postgres, SQLite, MySQL, Ecto

**Requirements**:

- Consistent read/write semantics across backends
- Support transactional operations where backend allows
- Lazy loading and streaming for large result sets
- Connection pooling and health checks
- Retry with exponential backoff
- Query interface must be backend-agnostic

### 5. Contexts Subsystem

**Purpose**: Standardized structure for domain logic and business rules.

**Structure**:

- Each context is an Elixir application
- Standard module organization:
  - `Comn.Context` - Protocol for context serialization/deserialization
  - `Comn.Contexts` - Behaviour defining the interface for event systems.
  - `Comn.Contexts.ContextStruct` - Standard context representation
  - `Comn.Contexts.PolicyStruct` - Standard policy representation
  - `Comn.Contexts.RuleStruct` - Standard rule representation

**Requirements**:

- Contexts must be independently testable
- Contexts must be composable
- Contexts must report errors via `Comn.Error`
- Contexts must publish events via `Comn.Event`
- Contexts must support RBAC via roles/permissions


### 6. Infra Subsystem

**Purpose**: Multi-cloud infrastructure management abstraction.

**Interfaces**:

- `Comn.Infra` - Behavior defining infrastructure management operations
- `Comn.Infra.NodeStruct` - Standard resource struct
- `Comn.Infra.LinkStruct` - Standard link struct
- `Comn.Infra.TagStruct` - Standard tag struct
- `Comn.Infra.Protocol` - Protocol for serialization/deserialization of links, nodes, tags

**Providers**:

- Proxmox
- Linux (LXC, KVM)
- AWS
- GCP
- Azure
- DigitalOcean
- Linode
- Hetzner
- Heroku
- Fly.io

### 7. Operational Requirements

**Purpose**: Shared infrastructure utilities for configuration, health, metrics, networking.

**Modules**:

#### 7.1 Configuration

- `Comn.Infra.Config` - unified config loading
- Support sources: environment, files (.exs, TOML), vaults
- Hot-reloadable configuration
- Config validation schemas

#### 7.2 Health & Diagnostics

- `Comn.Infra.Health` - health check abstraction
- Dependency health (DB, cache, queue, auth service)
- Diagnostic endpoints
- Liveness and readiness probes

#### 7.3 Metrics & Observability

- `Comn.Infra.Metrics` - standard metric types
  - Counter
  - Gauge
  - Histogram
  - Distribution
- OpenTelemetry integration
- Exporters: Prometheus, Datadog, CloudWatch, GCP Monitoring

#### 7.4 Networking

- `Comn.Infra.Http` - HTTP client
  - Retry strategies
  - Circuit breaker
  - Timeout handling
  - Request/response logging
- `Comn.Infra.Rpc` - RPC abstraction
  - gRPC support
  - JSON-RPC support
  - Service discovery

#### 7.5 Process Management

- `Comn.Infra.Supervisor` - standard supervision patterns
- `Comn.Infra.Actor` - common actor patterns
  - State managers
  - Work queues
  - Schedulers
  - Pipelines

**Requirements**:

- Configuration must be immutable after boot
- Health checks must be fast (< 100ms)
- Metrics must have negligible overhead
- HTTP client must support timeouts and retries
- Supervision must support graceful shutdown

## Non-Functional Requirements

### Performance

- Abstraction overhead < 5% vs direct library usage
- Event publishing: < 10ms latency (local backend)
- Config loading: < 1s for typical config
- Health checks: < 100ms per check
- Metrics recording: < 1μs per metric

### Reliability

- All operations must be failure-tolerant
- Transactional guarantees where backend supports
- Circuit breakers on external calls
- Graceful degradation when backends unavailable
- Comprehensive error reporting

### Maintainability

- Extensive test coverage (>85% line coverage)
- Gherkin-based acceptance tests
- Clear separation of concerns
- Well-documented interfaces
- Semantic-first design

### Observability

- Full distributed tracing support (correlation IDs)
- Structured logging
- Metrics for all major operations
- Health check endpoints
- Diagnostic utilities

### Security

- No credentials in logs
- Support for mTLS
- Input validation by default
- RBAC support
- Audit trail for secrets access

## Data Models

### Error Model

```yang
ErrorStruct:
  - id: UUID
  - message: string
  - category: enum (validation|persistence|network|auth|internal)
  - severity: enum (low|medium|high|critical)
  - details: map
  - stacktrace: [string]
  - context: map
  - timestamp: datetime
```

### Event Model

```yang
Event:
  - id: UUID
  - type: string (domain.action format)
  - timestamp: datetime
  - correlation_id: UUID
  - causation_id: UUID (optional)
  - metadata: map
  - payload: any (schema-validated)
  - version: integer
```

### Secret Model

```yang
Secret:
  - key: string
  - value: string (encrypted)
  - version: integer
  - rotation_policy: enum (manual|time_based|event_based)
  - rotation_interval: duration (if time_based)
  - expires_at: datetime (optional)
  - created_at: datetime
  - rotated_at: datetime
```

## Action Models (Petri Net Sketches)

### Event Processing

```cpn
publish -> [Registry|NATS|RabbitMQ|Kafka] -> subscribers -> handlers
                                          -> errors reported
                                          -> metrics recorded
```

### Error Handling

```cpn
operation -> error -> ErrorProtocol -> ErrorStruct -> logging -> reporting
                                                    -> recovery
                                                    -> escalation
```

### Repo Transaction

```cpn
begin -> [read|write|delete] -> [success -> commit] -> end
                             -> [failure -> rollback] -> retry
```

## Acceptance Criteria

All features must be validated via Gherkin-based acceptance tests:

### Errors

- [ ] An error can be converted to ErrorStruct
- [ ] ErrorStruct can be serialized to Comn.Events for publishing
- [ ] Errors include stacktraces and context
- [ ] Errors support categorization
- [ ] Exceptions are caught and converted automatically
- [ ] Backends are swappable via config
- [ ] Backends are transparent to code

### Events

- [ ] An event can be published
- [ ] A subscriber can receive published events
- [ ] Events have unique IDs and correlation IDs
- [ ] Event payloads are schema-validated
- [ ] Backends are swappable via config
- [ ] Backends are transparent to code

### Secrets

- [ ] A secret can be stored and retrieved
- [ ] Secrets are never logged
- [ ] Secrets can be rotated
- [ ] Rotation policies are enforced
- [ ] Backends are swappable via config
- [ ] Backends are transparent to code

### Repos

- [ ] Data can be read from any repo backend
- [ ] Data can be written to any repo backend
- [ ] Transactions are supported where backend allows
- [ ] Queries are backend-agnostic
- [ ] Backends are swappable via config
- [ ] Backends are transparent to code

### Contexts

- [ ] A context can be created
- [ ] Services within a context are testable
- [ ] Contexts publish events
- [ ] Contexts report errors
- [ ] Contexts are composable
- [ ] Backends are swappable via config
- [ ] Backends are transparent to code

### Infra

-[ ] A provider can be configured
-[ ] A compute resource can be managed through the entire lifecycle (creation, operation, update, deletion) using infrastructure as code (IaC) principles
-[ ] A network resource can be managed through the entire lifecycle (creation, operation, update, deletion) using infrastructure as code (IaC) principles
-[ ] A storage resource can be managed through the entire lifecycle (creation, operation, update, deletion) using infrastructure as code (IaC) principles
-[ ] Access controls can be applied to resources
-[ ] Resources can be tagged and organized across multiple providers
-[ ] Resource usage can be monitored and reported across multiple providers
-[ ] Resources can be scaled up and down based on demand across multiple providers
-[ ] Resources can be backed up and restored across multiple providers
-[ ] Resources can be audited for compliance across multiple providers
-[ ] Resources can be integrated with other services and tools across multiple providers
-[ ] Resources can be automated using GitOps principles
-[ ] Resources can be defined using declarative configuration files
-[ ] Backends are swappable via config
-[ ] Backends are transparent to code

### Operational

- [ ] Configuration can be loaded from multiple sources
- [ ] Health checks can be performed
- [ ] Metrics can be recorded and exported
- [ ] HTTP requests can be made with retry/circuit breaker
- [ ] Supervision trees can be started/stopped gracefully

## Release Plan

### Phase 1 (MVP - Q1 2026)

- [x] Project scaffold
- [ ] Supervision tree
- [ ] Errors subsystem (core)
- [ ] Events subsystem (Registry backend)
- [ ] Repo: Table, Graph types with basic backends
- [ ] Config system
- [ ] Acceptance test framework
- [ ] Secrets: environment/file/Vault backends

### Phase 2 (Q2 2026)

- [ ] Events: NATS backend
- [ ] Repo: Column, Stream, Queue types
- [ ] Infra: Proxmox, Linux, AWS providers
- [ ] Health checks and diagnostics
- [ ] Metrics collection and OpenTelemetry

### Phase 3 (Q3 2026)

- [ ] Contexts standardization
- [ ] Advanced supervision patterns
- [ ] All remaining repo types
- [ ] Infra: GCP, Azure providers

### Phase 4 (Q4 2026)

- [ ] Remaining backends for all repo types
- [ ] Performance optimization
- [ ] Documentation and examples
- [ ] Production hardening

## Success Metrics

1. **Adoption**: 3+ open-source projects, 2+ production deployments in first year
2. **Performance**: < 5% overhead vs direct library usage
3. **Developer Experience**: 50% reduction in infrastructure setup time
4. **Reliability**: 99.9% availability for abstraction layer
5. **Test Coverage**: >= 85% line coverage
6. **Documentation**: All interfaces have examples and benchmarks

## Constraints & Assumptions

### Constraints

- Must run on BEAM (Erlang 26+)
- Must support Elixir 1.14+
- Configuration must be immutable after startup
- All async operations must be non-blocking

### Assumptions

- Applications will use standard OTP patterns
- Backend services (DB, queue, etc.) are available
- Developers want semantic-first interfaces
- Small pieces, loosely joined philosophy is preferred

## Open Questions & Decisions Needed

1. **Repo Query Language**: SQL-like DSL or Elixir-native macros?
2. **Error Severity Levels**: Are 5 levels sufficient or need more granularity?
3. **Event Guarantees**: Exactly-once vs at-least-once semantics per backend?
4. **Config Hot-Reload**: Full reload vs selective re-evaluation?
5. **Metrics Cardinality**: Limits on tag/label combinations?
