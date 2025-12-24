---
title: "Comn Framework - Data Models"
create-date: 20251223
update-date:
---

# Data Models

This document defines the data structures for all Comn subsystems using YANG notation. These models establish the contract between application code and backend implementations.

## Design Principles

1. **Immutability** - Structs represent snapshots, not mutable state
2. **Self-describing** - All entities carry metadata about themselves
3. **Traceable** - Support correlation and causation tracking
4. **Versionable** - Structs support versioning for evolution
5. **Serializable** - All types must be convertible to/from external formats

---

## 1. Errors Subsystem

### ErrorStruct

Standard representation for all errors in the system.

---

## 2. Events Subsystem

### EventStruct

Standard representation for domain and system events.

### EventLogEntry

Internal structure for event log storage.

---

## 3. Secrets Subsystem

### SecretStruct

Standard representation for managed secrets.

---

## 4. Repositories Subsystem

### RepoStruct

Base structure for repository metadata.

```yang

```

### QueryStruct

Standard query representation.

---

## 5. Context Subsystem

### ContextStruct

Execution context for programs and agents.

### PolicyStruct

Policy definition for context-based rules.

### RuleStruct

Individual rule within a policy.

---

## 6. Infrastructure Subsystem

### NodeStruct

Infrastructure node (compute, storage, network device).

### LinkStruct

Network link or relationship between nodes.

### TagStruct

Key-value tag for resource organization.

### ConfigStruct

Configuration entry.

### HealthCheckStruct

Health check result.

---

## Common Types

### UUID

All UUIDs are version 4 (random) represented as lowercase hyphenated strings:
`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`

### Timestamp

All timestamps are ISO8601 format with timezone:
`YYYY-MM-DDTHH:MM:SS.sssZ` or `YYYY-MM-DDTHH:MM:SS.sss+HH:MM`

### Maps/Dictionaries

YANG `container` without explicit leaves represents a map/dictionary where:

- Keys are strings
- Values are any valid Elixir term
- Serialization format depends on backend (JSON, MessagePack, ETF, etc)

---

## Validation Rules

1. **Mandatory fields** - Must be present and non-null
2. **UUIDs** - Must be valid v4 UUIDs
3. **Timestamps** - Must be valid ISO8601
4. **Enums** - Must match defined enumeration values exactly
5. **Integers** - Must be within type bounds (uint32: 0-4294967295, etc)
6. **Strings** - No length limits unless specified

---

## Evolution Strategy

1. **Add fields** - Safe, old code ignores new fields
2. **Rename fields** - Add new field, deprecate old, remove in major version
3. **Change types** - Requires major version bump
4. **Remove fields** - Deprecate first, remove in major version
5. **Version field** - Use `version` field in structs to handle schema evolution

---
