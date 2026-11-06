import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("WakeUp")
                .font(.largeTitle.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
