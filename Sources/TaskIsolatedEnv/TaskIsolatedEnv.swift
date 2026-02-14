import Foundation

public protocol TaskIsolatedEnvType {
    static var liveValue: Self { get }
}

private struct EnvBox: @unchecked Sendable {
    let value: Any
}

private enum TaskLocalEnvRegistry {
    @TaskLocal static var values: [ObjectIdentifier: EnvBox] = [:]
}

private func taskLocalEnvOverride<Env>(_ type: Env.Type) -> Env? {
    TaskLocalEnvRegistry.values[ObjectIdentifier(type)]?.value as? Env
}

#if DEBUG
private enum PreparedEnvRegistry {
    static let lock = NSRecursiveLock()
    static var values: [ObjectIdentifier: EnvBox] = [:]

    static func value<Env>(for type: Env.Type) -> Env? {
        lock.lock()
        defer { lock.unlock() }
        return values[ObjectIdentifier(type)]?.value as? Env
    }

    static func set<Env>(_ value: Env, for type: Env.Type) {
        lock.lock()
        defer { lock.unlock() }
        values[ObjectIdentifier(type)] = .init(value: value)
    }

    static func remove<Env>(for type: Env.Type) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: ObjectIdentifier(type))
    }

    static func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}

private func preparedEnvOverride<Env>(_ type: Env.Type) -> Env? {
    PreparedEnvRegistry.value(for: type)
}
#endif

public func currentTaskIsolatedEnv<Env: TaskIsolatedEnvType>(_ type: Env.Type = Env.self) -> Env {
#if DEBUG
    if let override = taskLocalEnvOverride(type) {
        return override
    }
    if let prepared = preparedEnvOverride(type) {
        return prepared
    }
#endif
    return type.liveValue
}

#if DEBUG

public func withTaskIsolatedEnv<Env: TaskIsolatedEnvType>(
    _ type: Env.Type = Env.self,
    override mutate: (inout Env) -> Void,
    operation: () throws -> Void
) rethrows {
    var value = currentTaskIsolatedEnv(type)
    mutate(&value)

    var values = TaskLocalEnvRegistry.values
    values[ObjectIdentifier(type)] = .init(value: value)
    try TaskLocalEnvRegistry.$values.withValue(values, operation: operation)
}

public func withTaskIsolatedEnv<Env: TaskIsolatedEnvType>(
    _ type: Env.Type = Env.self,
    override mutate: (inout Env) -> Void,
    operation: () async throws -> Void
) async rethrows {
    var value = currentTaskIsolatedEnv(type)
    mutate(&value)

    var values = TaskLocalEnvRegistry.values
    values[ObjectIdentifier(type)] = .init(value: value)
    try await TaskLocalEnvRegistry.$values.withValue(values, operation: operation)
}

public func prepareTaskIsolatedEnv<Env: TaskIsolatedEnvType>(
    _ type: Env.Type = Env.self,
    override mutate: (inout Env) throws -> Void
) rethrows {
    var value = type.liveValue
    try mutate(&value)
    PreparedEnvRegistry.set(value, for: type)
}

public func prepareTaskIsolatedEnv<Env: TaskIsolatedEnvType>(
    _ type: Env.Type = Env.self,
    override mutate: (inout Env) async throws -> Void
) async rethrows {
    var value = type.liveValue
    try await mutate(&value)
    PreparedEnvRegistry.set(value, for: type)
}

public func resetPreparedTaskIsolatedEnv<Env: TaskIsolatedEnvType>(_ type: Env.Type = Env.self) {
    PreparedEnvRegistry.remove(for: type)
}

public func resetPreparedTaskIsolatedEnvs() {
    PreparedEnvRegistry.removeAll()
}

#endif
