# TaskIsolatedEnv

`TaskIsolatedEnv` is a tiny task-local environment helper for Swift concurrency.

Requires Swift 6.2 or later and builds in Swift 6 language mode.

It is inspired by [Point-Free's Dependencies](https://github.com/pointfreeco/swift-dependencies), but intentionally much smaller and opinionated.

## Core Idea

- Provide an environment that encapsulates all the dependencies in one place.
- Lock the environment in release builds so configuration cannot be accidentally changed at runtime.
- Allow overrides in debug when you need test or preview configuration.

`TaskIsolatedEnv` does this by design:
- `currentTaskIsolatedEnv` returns `liveValue` in release.
- Override APIs are available only in debug.

## Design Rules

- One root environment per boundary conforms to `TaskIsolatedEnvType`.
  - App boundary: `appEnv`
  - Package boundary: `packageEnv` (only if that package needs its own environment)
- Nested groups are plain structs (not `TaskIsolatedEnvType`).
- Overrides happen only at the root environment.
- Access stays explicit and consistent: `appEnv.api.fetchUser(...)`.

This keeps a single source of truth for environment values inside a boundary.

## Small Example

```swift
import TaskIsolatedEnv

struct User: Equatable, Sendable {
    var id: Int
    var name: String
}

struct APIClient: Sendable {
    var fetchUser: @Sendable (_ id: Int) async throws -> User
    var searchUsers: @Sendable (_ query: String) async throws -> [User]

    static func fetchUser(id: Int) async throws -> User {
        ...
    }

    static func searchUsers(_ query: String) async throws -> [User] {
        ...
    }

    static let live = APIClient(
        fetchUser: Self.fetchUser,
        searchUsers: Self.searchUsers
    )
}

struct AppEnv: TaskIsolatedEnvType {
    var api: APIClient
    var showDebugBadge: Bool

    static let liveValue = Self(api: .live, showDebugBadge: false)
}

var appEnv: AppEnv {
    currentTaskIsolatedEnv(AppEnv.self)
}

func profileTitle(userID: Int) async throws -> String {
    let user = try await appEnv.api.fetchUser(userID)
    return appEnv.showDebugBadge ? "[DBG] \(user.name)" : user.name
}

// Debug/test scope: override only one endpoint.
await withTaskIsolatedEnv(AppEnv.self, override: { env in
    env.api.fetchUser = { id in User(id: id, name: "Test user \(id)") }
}) {
    _ = try await appEnv.api.fetchUser(42)        // overridden
    _ = try await appEnv.api.searchUsers("anna")  // unchanged (still live)
}
```

## API Guide

- `currentTaskIsolatedEnv(Type.self)`
  - Reads the current environment value.
  - In release, this is always `Type.liveValue`.
  - In debug, it can read prepared or task-scoped overrides.

- `withTaskIsolatedEnv(Type.self, override:operation:)`
  - Use this for tests and short-lived scoped overrides.
  - The override is active only inside `operation`.
  - Nested scopes are supported and values are restored automatically.
  - This does not leak across tests when used as intended.

- `prepareTaskIsolatedEnv(Type.self, override:)`
  - Use this for Xcode previews (and app startup-style setup) where there is no natural scoped operation.
  - The prepared value stays active until replaced or reset.
  - Preview pattern:

```swift
#Preview {
    prepareTaskIsolatedEnv(AppEnv.self, override: { env in
        env.showDebugBadge = true
    })
    return FeatureView()
}
```

- `resetPreparedTaskIsolatedEnv(Type.self)` and `resetPreparedTaskIsolatedEnvs()`
  - These clear prepared (persistent) overrides.
  - Usually not needed for normal tests because tests should prefer `withTaskIsolatedEnv`.
  - Useful when you use `prepareTaskIsolatedEnv` in long-lived processes and want explicit cleanup.

## Migrating to 1.1.0

- Use a Swift 6.2 or later compiler. Clients may use Swift 5 or Swift 6 language mode.
- `TaskIsolatedEnvType` now inherits `Sendable`, so the compiler checks that stored environments can safely be shared
  between tasks. Nested dependency types must also be `Sendable`; public structs need an explicit conformance.
- Environment closure properties should be `@Sendable`, or `@MainActor` when they access UI state.
- The general scoped closures no longer require `@Sendable`. They can capture caller-local state because the async
  scoped and preparation functions use `nonisolated(nonsending)` to inherit the caller's actor.
- Function names, argument lists, and explicit `@MainActor` overloads are preserved. Existing call syntax and
  task-local override behavior remain the same.

## Optional Package Root

If a reusable package needs its own environment, define a package-local root env and access it directly:

```swift
public struct PackageEnv: TaskIsolatedEnvType {
    public static let liveValue = PackageEnv()
}

public var packageEnv: PackageEnv {
    currentTaskIsolatedEnv(PackageEnv.self)
}
```

`packageEnv` should be used directly, not as a property of `appEnv`.

## Behavior

- `currentTaskIsolatedEnv` reads task-scoped overrides first in debug, then prepared overrides.
- `withTaskIsolatedEnv` exists only in debug builds and is operation-scoped.
- `prepareTaskIsolatedEnv` exists only in debug builds and is persistent until reset/replaced.
- Overrides support nesting: inner scopes shadow outer scopes, and values are restored on exit.
- The compiler ensures that the environment is locked in release builds.
