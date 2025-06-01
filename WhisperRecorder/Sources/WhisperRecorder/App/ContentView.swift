import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "mic.circle")
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            Text("WhisperRecorder")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
            
            Text("Voice recording and transcription tool")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
} 