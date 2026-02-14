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

        withTaskIsolatedEnv(TestEnv.self, override: { $0.value = 42 }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 42)
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
    }

    @Test
    func closurePropertyOverride() {
        #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "value:2")

        withTaskIsolatedEnv(TestEnv.self, override: { $0.formatValue = { "override:\($0)" } }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "override:2")
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).formatValue(2) == "value:2")
    }

    @Test
    func nestedOverridesRestoreOuterValue() {
        withTaskIsolatedEnv(TestEnv.self, override: { $0.value = 10 }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 10)

            withTaskIsolatedEnv(TestEnv.self, override: { $0.value = 20 }) {
                #expect(currentTaskIsolatedEnv(TestEnv.self).value == 20)
            }

            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 10)
        }

        #expect(currentTaskIsolatedEnv(TestEnv.self).value == 1)
    }

    @Test
    func asyncScopeInheritedByChildTaskButNotDetachedTask() async {
        await withTaskIsolatedEnv(TestEnv.self, override: { $0.value = 99 }) {
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

                    await withTaskIsolatedEnv(TestEnv.self, override: { $0.value = i }) {
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

        withTaskIsolatedEnv(TestEnv.self, override: { $0.value = 7 }) {
            #expect(currentTaskIsolatedEnv(TestEnv.self).value == 7)
            #expect(currentTaskIsolatedEnv(OtherTestEnv.self).name == "live")

            withTaskIsolatedEnv(OtherTestEnv.self, override: { $0.name = "test" }) {
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
