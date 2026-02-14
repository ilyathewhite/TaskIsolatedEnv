public protocol TaskIsolatedEnvType {
    static var liveValue: Self { get }
}

private struct TaskLocalEnvBox: @unchecked Sendable {
    let value: Any
}

private enum TaskLocalEnvRegistry {
    @TaskLocal static var values: [ObjectIdentifier: TaskLocalEnvBox] = [:]
}

private func taskLocalEnvOverride<Env>(_ type: Env.Type) -> Env? {
    TaskLocalEnvRegistry.values[ObjectIdentifier(type)]?.value as? Env
}

public func currentTaskIsolatedEnv<Env: TaskIsolatedEnvType>(_ type: Env.Type = Env.self) -> Env {
#if DEBUG
    if let override = taskLocalEnvOverride(type) {
        return override
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
#endif
