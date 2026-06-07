import Testing
@testable import Cribble

struct RunnerCredentialStoreTests {
    @Test
    func normalizesRunnerAccountKeys() {
        #expect(
            RunnerCredentialStore.accountKey(for: " HTTPS://AI.EXAMPLE.COM/v1 ")
                == "https://ai.example.com/v1"
        )
    }
}
