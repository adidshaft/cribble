import Foundation

enum RemoteRunnerDataBoundary {
    static let detail = "Prompts, note excerpts, generated summaries, and embedding requests may leave this Mac for the selected runner."
}

enum RemoteRunnerSetupReview {
    static let markdown = """
    # Remote Runner Setup Review

    Runner name:
    Endpoint:
    Model:
    Embeddings:
    Trust label:

    Context boundary:
    \(RemoteRunnerDataBoundary.detail)

    API key:
    Store credentials in Keychain. Do not put secrets in manifests, notes, examples, fixtures, or docs.

    Approval checklist:
    - Endpoint is controlled by the user, team, or trusted vendor.
    - Retention policy, logging, and access controls are understood before use.
    - Requested note context is appropriate for this runner.
    - Secrets stay out of manifests and notes; use Keychain only.
    - Disable path is understood before approval.

    Disable/revoke:
    Choose a different runner, clear the API key, or disable/remove the contributing extension in Settings.
    """
}

enum DecisionLogTemplate {
    static let markdown = """
    ## YYYY-MM-DD - Decision title

    Status: proposed | accepted | reversed
    Owner:

    Context:

    Decision:

    Evidence:
    - [[Research Review]]
    - [[Tasks and Intelligence]]

    Follow-up:
    - [ ] Add task
    - [ ] Review in Project Intelligence

    Review boundary:
    - What did Cribble read?
    - What may leave this Mac?
    - What can be disabled or reverted?
    """
}

enum ResearchReviewTemplate {
    static let markdown = """
    # Research Review

    Goal:

    Scope:

    Sources reviewed:
    - [[Source note]]

    Claim table:
    | Claim | Evidence | Confidence | What would change my mind? |
    | --- | --- | --- | --- |
    |  |  |  |  |

    Contradictions or gaps:
    -

    Decisions or recommendations:
    -

    Follow-up:
    - [ ] Add missing source
    - [ ] Review with Project Intelligence

    Review boundary:
    - What did Cribble read?
    - Did any note context leave this Mac?
    - Which generated artifact was copied or saved?
    """
}

enum ProductReadinessCheckpointTemplate {
    static let markdown = """
    # Product Readiness Checkpoint

    Branch:
    Date:
    Owner:

    ## Strong product signal

    -

    ## Ready to keep

    | Area | Evidence |
    | --- | --- |
    |  |  |

    ## Stop conditions

    Stop and design separately if the next change needs:

    - executable plugin runtime;
    - signed bundle loading;
    - hidden extension execution;
    - broad project reads without a consent boundary;
    - source-note writes without preview/review/cancel;
    - secrets in manifests, docs, examples, fixtures, tests, or DemoNotes;
    - non-native extension UI without explicit maintainer approval;
    - remote intelligence that hides retention, logging, endpoint ownership, or revocation.

    ## Keep going only if

    -

    ## Verification snapshot

    - Tests:
    - Manual checks:
    - Known residual noise:

    ## Not done on purpose

    -
    """
}
