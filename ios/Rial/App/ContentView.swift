import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Rial")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Native iOS App")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
