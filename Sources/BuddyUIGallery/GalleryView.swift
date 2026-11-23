import BuddyCore
import BuddyUI
import Observation
import SwiftUI

@MainActor @Observable
final class GalleryController {
    var state: GalleryState = .demo
    var showSidebar = true
    var cycling = false
}

struct GalleryRoot: View {
    @Bindable var controller: GalleryController

    var body: some View {
        HStack(spacing: 0) {
            if controller.showSidebar {
                sidebar
                Divider()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(controller.state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    StageTile(state: controller.state, scheme: .dark, backdrop: .dark, caption: "Dark appearance, dark desktop")
                    StageTile(state: controller.state, scheme: .dark, backdrop: .light, caption: "Dark appearance, light desktop")
                    StageTile(state: controller.state, scheme: .light, backdrop: .light, caption: "Light appearance, light desktop")
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.5))
        .task(id: controller.cycling) {
            guard controller.cycling else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                let all = GalleryState.allCases.filter { $0 != .demo }
                let i = all.firstIndex(of: controller.state) ?? -1
                controller.state = all[(i + 1) % all.count]
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Cycle every 3 s", isOn: $controller.cycling)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            List(GalleryState.allCases, selection: Binding(
                get: { controller.state },
                set: { if let s = $0 { controller.state = s } }
            )) { state in
                Text(state.title).tag(state)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 220)
        .background(.background)
    }
}

enum Backdrop {
    case dark, light
}

struct StageTile: View {
    let state: GalleryState
    let scheme: ColorScheme
    let backdrop: Backdrop
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stage(state: state, backdrop: backdrop)
                .id(state)
                .environment(\.colorScheme, scheme)
                .frame(width: 372, height: 600)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.15))
        }
    }
}

private struct Stage: View {
    let state: GalleryState
    let backdrop: Backdrop
    @State private var model: BuddyModel
    @State private var bridge = BuddyComposeBridge { text, target in
        print("onCompose", text, target)
    }

    init(state: GalleryState, backdrop: Backdrop) {
        self.state = state
        self.backdrop = backdrop
        _model = State(initialValue: state.makeModel())
    }

    var body: some View {
        BuddyRootView(model: model, composeBridge: bridge)
            .buddyMaterialBlending(.withinWindow)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                FakeDesktop(backdrop: backdrop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
        .task {
            if state == .demo { await Fake.runDemo(model) }
        }
    }
}

/// Stand-in desktop with text and colour blocks, to judge glass legibility.
private struct FakeDesktop: View {
    let backdrop: Backdrop

    var body: some View {
        let dark = backdrop == .dark
        ZStack(alignment: .topLeading) {
            (dark ? Color(red: 0.10, green: 0.11, blue: 0.13) : Color(white: 0.95))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.20, green: 0.45, blue: 0.90)).frame(width: 90, height: 60)
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.55, blue: 0.20)).frame(width: 90, height: 60)
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.25, green: 0.70, blue: 0.45)).frame(width: 90, height: 60)
                }
                ForEach(0..<14, id: \.self) { i in
                    Text(Self.lines[i % Self.lines.count])
                        .font(.system(size: i % 5 == 0 ? 15 : 12, weight: i % 5 == 0 ? .bold : .regular))
                        .foregroundStyle(dark ? Color(white: 0.75) : Color(white: 0.15))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: dark ? 0.85 : 0.10)).frame(width: 120, height: 70)
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.80, green: 0.20, blue: 0.40)).frame(width: 150, height: 70)
                }
                ForEach(0..<10, id: \.self) { i in
                    Text(Self.lines[(i + 3) % Self.lines.count])
                        .font(.system(size: 12))
                        .foregroundStyle(dark ? Color(white: 0.7) : Color(white: 0.2))
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
    }

    static let lines = [
        "Release notes: picker keyboard navigation and recent fallback",
        "The quick brown fox jumps over the lazy dog while the build runs",
        "SELECT Id, Name FROM Opportunity WHERE StageName = 'Closed Won'",
        "func entries(from startDate: Date, mode: Mode) -> Entries",
        "Meeting notes, action items and owners for the next sprint",
        "Error budget remaining this quarter: 82 percent",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
    ]
}
