import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TakeLayer")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("スマホで撮った演奏を、DAW完成音源つきの動画に整える。")
                .font(.body)
            Text("Phase 0: 設計固定・リポジトリ土台")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
