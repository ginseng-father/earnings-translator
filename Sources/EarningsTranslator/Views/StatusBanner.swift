import SwiftUI

struct StatusBanner: View {
    let banner: Banner
    let chooseFolder: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if case .saveFailed = banner {
                Button("폴더 다시 선택", action: chooseFolder)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.15))
    }

    private var message: String {
        switch banner {
        case .ollamaUnreachable:
            return "Ollama에 연결할 수 없습니다. 터미널에서 `ollama serve`를 실행하세요. 받아쓰기는 계속되고, 연결되면 밀린 문장부터 번역합니다."
        case .modelMissing(let model):
            return "번역 모델이 없습니다. 터미널에서 `ollama pull \(model)`을 실행하세요."
        case .translationDelayed(let backlog):
            return "번역 지연 중 — \(backlog)문장 대기"
        case .permissionDenied:
            return "브라우저 소리가 들리지 않습니다. 영상이 재생 중인지 확인하고, 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 EarningsTranslator를 허용하세요."
        case .speechPermissionDenied:
            return "음성 인식 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 음성 인식에서 EarningsTranslator를 허용하세요."
        case .speechUnavailable:
            return "영어 음성 인식을 준비하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시작하세요(처음 한 번 음성 모델을 내려받습니다)."
        case .speechAssetDownloading(let progress):
            return "영어 음성 모델을 내려받는 중… \(Int(progress * 100))%"
        case .noBrowserAudio(let name):
            return "\(name)에서 아직 소리가 나지 않았습니다. 영상을 먼저 재생한 뒤 시작을 누르세요."
        case .saveFailed(let reason):
            return "저장하지 못했습니다: \(reason) 대본은 앱에 그대로 남아 있습니다."
        case .browserQuit:
            return "브라우저가 종료되어 번역을 멈추고 대본을 저장했습니다."
        }
    }

    private var icon: String {
        switch banner {
        case .translationDelayed, .speechAssetDownloading: return "hourglass"
        case .browserQuit: return "checkmark.circle"
        default: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch banner {
        case .translationDelayed, .speechAssetDownloading, .browserQuit: return .blue
        default: return .orange
        }
    }
}
