---
title: "MRD: Comn Framework"
create-date: 20250913
update-date: 20251223
---

# Market Requirements Document

## Product Concept

Comn is a framework that eliminates boilerplate infrastructure code by providing uniform abstract interfaces, data structures, and actions for six common program infrastructure needs. It provides a stable and sufficient surface for programs to be written against, allowing backend products, services, or paradigms to be changed without forcing changes to the consumers of the abstractions.

## Market Problem

### Repetition of Baseline Infrastructure Code

Elixir developers repeatedly solve the same foundational problems in every project, reinventing abstractions for:

1. **Context** — the surroundings, circumstances, environment, background, or settings that determine, specify, or clarify meaning for the functions of a program or system. Useful for abstracting and conveying policy and for abstracting instructions and constraints to digital agents.

2. **Events** — projects need a standard way to define, publish, and consume domain and system events. Ad hoc implementations lead to fragmentation and inconsistent event handling patterns.

3. **Errors** — error handling, categorization, and reporting are inconsistent across projects, making recovery, logging, and debugging harder. Each team reinvents error structures and propagation patterns.

4. **Repositories** — a location for safe storage and data preservation. Persistence layers (Ecto repos, ETS, Mnesia, Postgres, Redis, S3, etc.) lack a unified abstraction, forcing applications to be tightly bound to chosen backends.

5. **Secrets** — management of credentials, tokens, and keys is scattered across config files and environment variables, often without rotation, versioning, or standard interfaces.

6. **Infrastructure** — an underlying base or foundation that provides the facilities and services needed for the functioning of a program or system of programs. Every team rebuilds service plumbing (configuration loading, health checks, metrics, supervision patterns, network clients), wasting time and introducing subtle bugs.

### Consequences of Fragmentation

- **Slower Time-to-Market**: Teams spend weeks rewriting infrastructure abstractions before building domain logic.
- **Technical Debt**: Projects accumulate one-off implementations that are hard to maintain and evolve.
- **Lock-In**: Applications get tightly coupled to specific libraries and infrastructure choices, making future migration costly.
- **Inconsistent Developer Experience**: Onboarding new developers is harder when every project reinvents these baselines differently.
- **Testing Complexity**: Without standard abstractions, testing requires complex mocking and stubbing of infrastructure dependencies.

## Target Market

- **Elixir developers** building distributed systems who need resilience, observability, and configurability without wasting time on boilerplate.
- **Startups and scale-ups** using Elixir as a core backend technology that want to accelerate delivery.
- **Consultancies and agencies** delivering Elixir projects for clients, where reusing a standardized base framework reduces cost and risk.
- **Platform engineers** building internal developer platforms who need consistent infrastructure abstractions across teams.

## Product Requirements

### Core Abstractions

Each abstraction must provide:
- **Protocol** — for converting domain types to standard representations
- **Behavior** — defining the interface backend implementations must satisfy
- **Struct** — standardized data structures for messages and entities
- **Implementations** — backend integrations following `Comn.<App>.<Module>` pattern

### 1. Context

Provides abstractions for program surroundings, policy, and agent instructions.

**Requirements:**
- Represent execution context (environment, settings, constraints)
- Support policy definition and evaluation
- Provide instructions and constraints for digital agents
- Enable context composition and inheritance

**Backend Examples:** Configuration files, environment variables, policy engines, agent frameworks

### 2. Events

Publish/subscribe abstraction with pluggable backends for domain and system events.

**Requirements:**
- Uniform Event struct (id, type, timestamp, correlation_id, metadata, payload)
- Publish and subscribe operations
- Backend-agnostic event handling
- Support for event filtering and routing

**Backend Examples:** Registry (local), NATS, RabbitMQ, Kafka, Redis Streams

### 3. Errors

Standardized error handling, categorization, and reporting.

**Requirements:**
- Uniform Error struct with category, severity, context
- Convert any error type (Exception, tuple, map) to standard format
- Support error propagation and recovery patterns
- Enable structured error logging and reporting

**Backend Examples:** Built-in protocol implementations, logging backends, error tracking services

### 4. Repositories

Common interface for safe storage and data preservation across diverse backends.

**Requirements:**
- Unified operations: get, set, delete, observe
- Support for different storage paradigms (key-value, relational, document, blob, graph)
- Backend-agnostic query capabilities where applicable
- Transactional semantics where backend supports

**Backend Examples:** ETS, Mnesia, Postgres, SQLite, Redis, S3, local filesystem

### 5. Secrets

Management of credentials, tokens, and keys with rotation and versioning.

**Requirements:**
- Secure storage and retrieval of sensitive values
- Support rotation policies and versioning
- Never log or expose secret values
- Audit trail for access

**Backend Examples:** Environment variables (dev), file-based (dev), HashiCorp Vault, AWS Secrets Manager, Azure Key Vault

### 6. Infrastructure

Foundation facilities and services for program operation.

**Requirements:**
- Configuration loading from multiple sources
- Health checks and diagnostics
- Metrics collection and export
- HTTP client with retry/circuit-breaker
- Supervision patterns and process management

**Backend Examples:** Runtime config, Prometheus, OpenTelemetry, various cloud providers

## Differentiation

### What Makes Comn Different

1. **Backend Agnosticism** — Applications written against Comn abstractions can change infrastructure backends without refactoring application logic. Swap Postgres for SQLite, Registry for NATS, or local files for S3 by changing configuration, not code.

2. **Uniform Abstraction Pattern** — Every subsystem follows the same structure:
   - `Comn.<App>` — Protocol for type conversion
   - `Comn.<Apps>` — Behavior defining backend interface
   - `Comn.<App>Struct` — Standard message/entity format
   - `Comn.<App>.<Module>` — Backend implementations

3. **Elixir-Native Philosophy** — Embraces OTP, supervisors, and lightweight processes rather than hiding them. Comn abstractions are BEAM-first, not ports of patterns from other ecosystems.

4. **Composable Building Blocks** — Small pieces, loosely joined. Developers use only the abstractions they need. No framework lock-in or required base classes.

5. **Required Characteristics, Not Features** — Comn implementations must have:
   - **Topology-agnostic** — work the same locally and distributed
   - **Interoperable** — standard protocols enable cross-system integration
   - **Observable** — built-in tracing and instrumentation hooks
   - **Testable** — acceptance test framework with clear feature definitions

### What Comn Is Not

- **Not an authentication framework** — sufficient solutions already exist (Guardian, Pow, etc.)
- **Not a web framework** — complements Phoenix and other frameworks, doesn't replace them
- **Not a product** for metrics/tracing/testing — these are *characteristics* Comn implementations must have

## Success Metrics

- **Boilerplate Reduction**: 50% reduction in infrastructure setup code across projects
- **Adoption**: 3+ open-source projects and 2+ production deployments in first year
- **Performance**: < 5% overhead compared to using infrastructure libraries directly
- **Backend Portability**: Developers can swap backends with configuration changes only (no code refactoring)
- **Test Coverage**: >= 85% line coverage with acceptance tests for all features
- **Developer Satisfaction**: Positive feedback on reduced onboarding time and consistent patterns

## Release Plan

### Phase 1: Foundation (TDD Setup)

**Define the standard abstractions**:
1. Create `arch/data-models.md` — document all struct definitions and data types
2. Create `arch/action-models.md` — document all behaviors and operations
3. Create `arch/features.md` — document feature requirements in Gherkin format
4. Establish testing framework with Cabbage for BDD

**Implement core abstractions** (following TDD):
- Errors subsystem with protocol and basic implementations
- Events subsystem with Registry backend
- Secrets subsystem with environment variable and file backends

**Deliverables**:
- [ ] Data models documented
- [ ] Action models documented
- [ ] Features documented with acceptance criteria
- [ ] Acceptance test framework operational
- [ ] Errors abstraction complete
- [ ] Events abstraction complete (Registry backend)
- [ ] Secrets abstraction complete (env + file backends)

### Phase 2: Expansion

**Add backends and capabilities**:
- Events: NATS backend
- Repositories: Initial implementation with ETS and local file backends
- Infrastructure: Configuration loading and health checks

**Deliverables**:
- [ ] Events: NATS backend operational
- [ ] Repositories abstraction with 2 backends
- [ ] Infrastructure: Config and health check modules

### Phase 3: Maturity

**Complete repository types and infrastructure**:
- Repositories: Add Postgres, Redis, S3 backends
- Infrastructure: Metrics, supervision patterns, HTTP client
- Context: Policy and agent instruction abstractions

**Deliverables**:
- [ ] Repository backends for common use cases
- [ ] Full infrastructure subsystem
- [ ] Context subsystem operational
- [ ] Production hardening and performance optimization

---
