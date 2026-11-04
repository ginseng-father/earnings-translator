import SwiftUI
import TranslatorSystem

/// Two rows: what to listen to and with which model, then the session controls.
struct ToolbarView: View {
    @Bindable var session: SessionController
    @Bindable var settings: Settings

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("브라우저", selection: $session.selectedBrowser) {
                    if session.browsers.isEmpty {
                        Text("실행 중인 브라우저 없음").tag(Browser?.none)
                    }
                    ForEach(session.browsers) { browser in
                        Text(browser.name).tag(Optional(browser))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(session.isRunning || session.isBusy)
                .onTapGesture { session.refreshBrowsers() }

                Picker("모델", selection: $settings.modelTag) {
                    ForEach(Settings.models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(session.isRunning || session.isBusy)

                Spacer()

                Toggle(isOn: $settings.pinOnTop) {
                    Image(systemName: settings.pinOnTop ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("켜면 모든 데스크톱과 전체 화면 영상 위에 항상 표시합니다. 끄면 일반 창처럼 원하는 데스크톱으로 옮길 수 있습니다.")
            }

            HStack(spacing: 8) {
                Button {
                    Task { session.isRunning ? await session.stop() : await session.start() }
                } label: {
                    Label(session.isRunning ? "정지" : "시작", systemImage: session.isRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 70)
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(session.isRunning ? .red : .accentColor)
                .disabled(session.selectedBrowser == nil || session.isBusy)

                Spacer()

                Button {
                    Task { await session.saveNow() }
                } label: {
                    Label("저장", systemImage: "square.and.arrow.down")
                }
                .help("누를 때마다 지금까지의 대본을 저장합니다. 정지 중에도 됩니다.")
                .disabled(session.segments.isEmpty)

                Button {
                    session.clear()
                } label: {
                    Label("정리", systemImage: "eraser")
                }
                .disabled(!session.canClear)
                .help("대본을 비웁니다. 저장된 파일은 그대로 남고, 다음 시작은 새 파일로 기록합니다.")
            }
        }
        .padding(10)
    }
}
