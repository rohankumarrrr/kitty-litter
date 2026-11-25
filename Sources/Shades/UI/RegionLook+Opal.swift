import AppKit
import ShadesContext

extension RegionLook {
    @MainActor static var opal: RegionLook {
        RegionLook(
            dim: Ink.hex(Opal.page).withAlphaComponent(0.42),
            halo: Ink.hex(Opal.white).withAlphaComponent(0.85),
            edge: Ink.hex(Opal.error),
            pillFill: Ink.hex(Opal.raised).withAlphaComponent(0.94),
            pillEdge: Ink.hex(Opal.white).withAlphaComponent(0.08),
            pillWords: MessagesInk.strong,
            hintFont: MessagesInk.font(ofSize: MessagesInk.body, weight: .medium),
            sizeFont: MessagesInk.font(ofSize: MessagesInk.meta, weight: .medium, tabular: true)
        )
    }
}
