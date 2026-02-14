import Testing
@testable import TaskIsolatedEnv

private struct TestEnv: TaskIsolatedEnvType, Equatable {
    var value: Int = 1
    var formatValue: @Sendable (_ value: Int) -> String = { "value:\($0)" }

    static func == (lhs: TestEnv, rhs: TestEnv) -> Bool {
        lhs.value == rhs.value
    }

    static let liveValue = TestEnv()
}

private struct OtherTestEnv: TaskIsolatedEnvType, Equatable {
    var name: String = "live"
    static let liveValue = OtherTestEnv()
}

#if DEBUG
private struct PreparedTestEnv: TaskIsolatedEnvType {
    var value: Int = 1
    static let liveValue = PreparedTestEnv()
}

private struct AsyncPreparedTestEnv: TaskIsolatedEnvType {
    var value: Int = 1
    static let liveValue = AsyncPreparedTestEnv()
}

private struct PreparedTestEnvA: TaskIsolatedEnvType {
    var value: Int = 1
    static let liveValue = PreparedTestEnvA()
}

private struct PreparedTestEnvB: TaskIsolatedEnvType {
    var value: Int = 2
    static let liveValue = PreparedTestEnvB()
}
#endif

struct TaskIsolatedEnvTests {
    @Test
    func currentValueUsesLiveByDefault() {
        let env = currentTaskIsolatedEnv(TestEnv.self)
        #expect(env.value == 1)
        #expect(env.formatValue(1) == "value:1")
    }

#if DEBUG
    @Test
    func syncScopedOverride() {
        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)

        withTaskIsolatedEnv(TestEnv.self, override: { env in
            env.value = 42
        }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 42)
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
    }

    @Test
    func closurePropertyOverride() {
        #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "value:2")

        withTaskIsolatedEnv(
            TestEnv.self,
            override: { env in
                env.formatValue = { "override:\($0)" }
            }
        ) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "override:2")
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "value:2")
    }

    @Test
    func nestedOverridesRestoreOuterValue() {
        withTaskIsolatedEnv(TestEnv.self, override: { env in
            env.value = 10
        }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 10)

            withTaskIsolatedEnv(TestEnv.self, override: { env in
                env.value = 20
            }) {
                #expect(currentTaskIsolatedEnv(TestEnv.self).value == 20)
            }

            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 10)
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
    }

    @Test
    func asyncScopeInheritedByChildTaskButNotDetachedTask() async {
        await withTaskIsolatedEnv(TestEnv.self, override: { env in
            env.value = 99
        }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 99)

            let inheritedValue = await Task {
                currentTaskIsolatedEnv(TestEnv.self).value
            }.value
            #expect(inheritedValue == 99)

            let detachedValue = await Task.detached {
                currentTaskIsolatedEnv(TestEnv.self).value
            }.value
            #expect(detachedValue == 1)
        }
    }

    @Test
    func concurrentSiblingOverridesDoNotLeak() async {
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<40 {
                group.addTask {
                    var allReadsWereScoped = true

                    await withTaskIsolatedEnv(TestEnv.self, override: { env in
                        env.value = i
                    }) {
                        for _ in 0..<20 {
                            if currentTaskIsolatedEnv(TestEnv.self).value != i {
                                allReadsWereScoped = false
                                return
                            }
                            await Task.yield()
                        }
                    }

                    return allReadsWereScoped && currentTaskIsolatedEnv(TestEnv.self).value == 1
                }
            }

            for await result in group {
                #expect(result)
            }
        }
    }

    @Test
    func differentEnvTypesAreIsolated() {
        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
        #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "live")

        withTaskIsolatedEnv(TestEnv.self, override: { env in
            env.value = 7
        }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 7)
            #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "live")

            withTaskIsolatedEnv(OtherTestEnv.self, override: { env in
                env.name = "test"
            }) {
                #expect(currentTaskIsolatedEnv(TestEnv.self).value == 7)
                #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "test")
            }

            #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "live")
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
        #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "live")
    }
#endif
}

#if DEBUG
@Suite("Prepared overrides", .serialized)
struct PreparedTaskIsolatedEnvTests {
    @Test
    func preparedOverridePersistsAndTaskScopedOverrideWinsInsideScope() {
        defer { resetPreparedTaskIsolatedEnv(PreparedTestEnv.self) }

        #expect(currentTaskIsolatedEnv(PreparedTestEnv.self).value == 1)

        prepareTaskIsolatedEnv(PreparedTestEnv.self, override: { env in
            env.value = 42
        })
        #expect(currentTaskIsolatedEnv(PreparedTestEnv.self).value == 42)

        withTaskIsolatedEnv(PreparedTestEnv.self, override: { env in
            env.value = 100
        }) {
            #expect(currentTaskIsolatedEnv(PreparedTestEnv.self).value == 100)
        }

        #expect(currentTaskIsolatedEnv(PreparedTestEnv.self).value == 42)

        resetPreparedTaskIsolatedEnv(PreparedTestEnv.self)
        #expect(currentTaskIsolatedEnv(PreparedTestEnv.self).value == 1)
    }

    @Test
    func asyncPreparedOverridePersistsOutsideScope() async {
        defer { resetPreparedTaskIsolatedEnv(AsyncPreparedTestEnv.self) }

        await prepareTaskIsolatedEnv(AsyncPreparedTestEnv.self, override: { env in
            await Task.yield()
            env.value = 77
        })

        #expect(currentTaskIsolatedEnv(AsyncPreparedTestEnv.self).value == 77)
    }

    @Test
    func resetAllPreparedOverridesClearsEveryPreparedValue() {
        defer { resetPreparedTaskIsolatedEnvs() }

        prepareTaskIsolatedEnv(PreparedTestEnvA.self, override: { env in
            env.value = 10
        })
        prepareTaskIsolatedEnv(PreparedTestEnvB.self, override: { env in
            env.value = 20
        })

        #expect(currentTaskIsolatedEnv(PreparedTestEnvA.self).value == 10)
        #expect(currentTaskIsolatedEnv(PreparedTestEnvB.self).value == 20)

        resetPreparedTaskIsolatedEnvs()

        #expect(currentTaskIsolatedEnv(PreparedTestEnvA.self).value == 1)
        #expect(currentTaskIsolatedEnv(PreparedTestEnvB.self).value == 2)
    }
}
#endif
