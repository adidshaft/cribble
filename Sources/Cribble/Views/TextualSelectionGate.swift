import SwiftUI
import Textual

extension View {
    @ViewBuilder
    func cribbleTextualSelection(_ enabled: Bool) -> some View {
        if enabled {
            textual.textSelection(.enabled)
        } else {
            textual.textSelection(.disabled)
        }
    }
}
