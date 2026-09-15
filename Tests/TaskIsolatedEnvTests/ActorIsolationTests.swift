import Testing
import TaskIsolatedEnv

#if DEBUG
private struct ActorIsolationEnv: TaskIsolatedEnvType {
    var value = 1
    static let liveValue = ActorIsolationEnv()
}

private struct ActorPreparedEnv: TaskIsolatedEnvType {
    var value = 1
    static let liveValue = ActorPreparedEnv()
}

private struct ConcurrentPreparedEnv: TaskIsolatedEnvType {
    var value = 0
    var negatedValue = 0
    static let liveValue = ConcurrentPreparedEnv()
}

private final class LocalValue {
    var value = 42
}

private actor Worker {
    var value = 42

    func checkScope() async {
        await withTaskIsolatedEnv(ActorIsolationEnv.self, override: { env in
            env.value = value
        }, operation: {
            await Task.yield()
            #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == value)
            value += 1
        })
        #expect(value == 43)
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }
}

struct ActorIsolationTests {
    @Test
    func generalFunctionReferencesKeepExistingTypes() async throws {
        let sync: (
            ActorIsolationEnv.Type,
            @Sendable (inout ActorIsolationEnv) -> Void,
            @Sendable () throws -> Void
        ) throws -> Void = withTaskIsolatedEnv
        let async: (
            ActorIsolationEnv.Type,
            @Sendable (inout ActorIsolationEnv) -> Void,
            @Sendable () async throws -> Void
        ) async throws -> Void = withTaskIsolatedEnv

        try sync(ActorIsolationEnv.self, { $0.value = 42 }, {
            #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 42)
        })
        try await async(ActorIsolationEnv.self, { $0.value = 43 }, {
            await Task.yield()
            #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 43)
        })
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }

    @Test @MainActor
    func mainActorFunctionReferencesKeepExistingTypes() async throws {
        let sync: @MainActor (
            ActorIsolationEnv.Type,
            @MainActor (inout ActorIsolationEnv) -> Void,
            @MainActor () throws -> Void
        ) throws -> Void = withTaskIsolatedEnv
        let async: @MainActor (
            ActorIsolationEnv.Type,
            @MainActor (inout ActorIsolationEnv) -> Void,
            @MainActor () async throws -> Void
        ) async throws -> Void = withTaskIsolatedEnv
        let local = LocalValue()

        try sync(ActorIsolationEnv.self, { $0.value = local.value }, {
            MainActor.assertIsolated()
            local.value = currentTaskIsolatedEnv(ActorIsolationEnv.self).value + 1
        })
        try await async(ActorIsolationEnv.self, { $0.value = local.value }, {
            await Task.yield()
            MainActor.assertIsolated()
            local.value = currentTaskIsolatedEnv(ActorIsolationEnv.self).value + 1
        })
        #expect(local.value == 44)
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }

    @Test @MainActor
    func mainActorSyncScopeAllowsLocalCaptures() {
        let local = LocalValue()
        withTaskIsolatedEnv(ActorIsolationEnv.self, override: { env in
            env.value = local.value
        }, operation: {
            MainActor.assertIsolated()
            local.value = currentTaskIsolatedEnv(ActorIsolationEnv.self).value + 1
        })
        #expect(local.value == 43)
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }

    @Test @MainActor
    func mainActorAsyncScopeAllowsLocalCaptures() async {
        let local = LocalValue()
        await withTaskIsolatedEnv(ActorIsolationEnv.self, override: { env in
            env.value = local.value
        }, operation: {
            await Task.yield()
            MainActor.assertIsolated()
            local.value = currentTaskIsolatedEnv(ActorIsolationEnv.self).value + 1
        })
        #expect(local.value == 43)
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }

    @Test
    func customActorScopePreservesIsolation() async {
        await Worker().checkScope()
    }

    @Test
    func throwingAsyncScopeRestoresEnvironment() async {
        enum Failure: Error { case expected }
        do {
            try await withTaskIsolatedEnv(ActorIsolationEnv.self, override: { $0.value = 42 }, operation: {
                await Task.yield()
                #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 42)
                throw Failure.expected
            })
            Issue.record("Expected scoped operation to throw")
        }
        catch {
            #expect(error is Failure)
        }
        #expect(currentTaskIsolatedEnv(ActorIsolationEnv.self).value == 1)
    }
}

extension PreparedTaskIsolatedEnvTests {
    @Test
    func concurrentPreparedReadsWritesAndResetsPreserveWholeValues() async {
        defer { resetPreparedTaskIsolatedEnv(ConcurrentPreparedEnv.self) }

        await withTaskGroup(of: Void.self) { group in
            for value in 1...40 {
                group.addTask {
                    for _ in 0..<20 {
                        prepareTaskIsolatedEnv(ConcurrentPreparedEnv.self, override: { env in
                            env.value = value
                            env.negatedValue = -value
                        })
                        await Task.yield()
                        let env = currentTaskIsolatedEnv(ConcurrentPreparedEnv.self)
                        #expect(env.value == -env.negatedValue)
                        resetPreparedTaskIsolatedEnv(ConcurrentPreparedEnv.self)
                    }
                }
            }
        }
    }

    @Test @MainActor
    func mainActorAsyncPreparationAllowsLocalCaptures() async {
        defer { resetPreparedTaskIsolatedEnv(ActorPreparedEnv.self) }
        let local = LocalValue()
        await prepareTaskIsolatedEnv(ActorPreparedEnv.self, override: { env in
            await Task.yield()
            MainActor.assertIsolated()
            env.value = local.value
            local.value += 1
        })
        #expect(currentTaskIsolatedEnv(ActorPreparedEnv.self).value == 42)
        #expect(local.value == 43)
    }
}
#endif
