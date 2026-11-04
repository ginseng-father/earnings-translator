import Observation
import SwiftUI
import TranslatorCore

/// Whether the transcript follows new lines. Kept outside the view because
/// @State needs a SwiftUI macro plugin that only ships with Xcode.
@MainActor @Observable
final class TranscriptScrollState {
    var followsLatest = true
    /// True while the user is dragging or flicking the scroll view. Only then
    /// does the scroll position change `followsLatest`; new lines growing the
    /// content below the viewport must not turn following off.
    var userIsScrolling = false
}

/// Scrolling transcript that follows new sentences until the user scrolls
/// up, then offers a button back to the latest line.
struct TranscriptView: View {
    let segments: [Segment]
    let liveEnglish: String?
    let scroll: TranscriptScrollState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments) { segment in
                        SegmentRow(segment: segment)
                        Divider()
                    }
                    if let liveEnglish {
                        LiveRow(english: liveEnglish)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, atBottom in
                if scroll.userIsScrolling {
                    scroll.followsLatest = atBottom
                }
            }
            .onScrollPhaseChange { _, phase in
                scroll.userIsScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onChange(of: segments) {
                if scroll.followsLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: liveEnglish) {
                if scroll.followsLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !scroll.followsLatest {
                    Button("최신으로") {
                        scroll.followsLatest = true
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(14)
                }
            }
            .overlay {
                if segments.isEmpty && liveEnglish == nil {
                    Text("브라우저를 고르고 시작을 누르세요.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
