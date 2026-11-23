import BuddyCore
import Observation

/// Carries the compose-field callback from the expanded panel to the app.
///
/// `BuddyModel` has no "send typed prompt" callback, so the panel's compose field reports here.
/// Integrator: create one bridge, set `onCompose`, pass it to `BuddyRootView(model:composeBridge:)`,
/// and dispatch the text with `SessionProviding.dispatch(prompt:screenshot:to:)` (screenshot nil).
/// The panel calls `onCompose` on the main actor and clears its draft right after.
/// Not actor-isolated itself so it can be BuddyRootView's default argument.
@Observable
public final class BuddyComposeBridge {
    public var onCompose: @MainActor (String, DispatchTarget) -> Void

    public init(onCompose: @escaping @MainActor (String, DispatchTarget) -> Void = { _, _ in }) {
        self.onCompose = onCompose
    }
}
