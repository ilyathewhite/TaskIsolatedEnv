# TaskIsolatedEnv

`TaskIsolatedEnv` is a tiny task-local environment helper for Swift concurrency.

It is inspired by [Point-Free's Dependencies](https://github.com/pointfreeco/swift-dependencies), but intentionally much smaller and opinionated.

## Core Idea

- Provide an environment that encapsulates all the dependencies in one place.
- Lock the environment in release builds so configuration cannot be accidentally changed at runtime.
- Allow scoped overrides for tests and previews.

`TaskIsolatedEnv` does this by design:
- `currentTaskIsolatedEnv` returns `liveValue` in release.
- `withTaskIsolatedEnv` is available only in debug.

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

struct User: Equatable {
    var id: Int
    var name: String
}

struct APIClient {
    var fetchUser: (_ id: Int) async throws -> User
    var searchUsers: (_ query: String) async throws -> [User]

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
await withTaskIsolatedEnv(AppEnv.self, override: {
    $0.api.fetchUser = { id in User(id: id, name: "Test user \(id)") }
}) {
    _ = try await appEnv.api.fetchUser(42)        // overridden
    _ = try await appEnv.api.searchUsers("anna")  // unchanged (still live)
}
```

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

- `currentTaskIsolatedEnv` reads task-local overrides only in debug.
- `withTaskIsolatedEnv` exists only in debug builds.
- Overrides support nesting: inner scopes shadow outer scopes, and values are restored on exit.
- The compiler ensures that the environment is locked in release builds.
