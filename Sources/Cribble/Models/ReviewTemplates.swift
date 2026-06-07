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
