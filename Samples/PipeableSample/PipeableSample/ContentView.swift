import SwiftUI

// swiftlint:disable line_length

struct ContentView: View {
    @State var showWeb = false
    @State var password = ""
    @State var centralIndex = 0
    @State private var items: [NewsItem] = []

    var body: some View {
        ZStack {
            MainScreen(items: $items) {
                showWeb = true
            }
            .sheet(isPresented: $showWeb) {
                PipeableWebViewWrapper(items: $items) {
                    showWeb = false
                }
            }
        }
    }
}

struct MainScreen: View {
    @Environment(\.colorScheme)
    var colorScheme

    @Binding var items: [NewsItem]
    var onButtonTapped: () -> Void

    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Spacer()
                    Text("Pipeable Demo")
                        .bold()
                        .font(.title.width(.expanded))

                    Spacer()
                }
            }

            HStack(alignment: .center) {
                Text(
                    """
                    Pipeable is a mobile webview automation framework.

                    In this demo we will show how one can automate searching for web automation posts on Hacker News and collecting the results.
                    """
                )
                // Full width.
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title3)
                .padding(.all, 10)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.secondary, lineWidth: 2)
                )
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(15)
                .padding(.all, 10)

                Spacer()
            }

            HStack {
                Image("YC")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30)
                    .padding()

                VStack(alignment: .leading) {
                    Button("Search Hacker News") {
                        onButtonTapped()
                    }
                    .font(.headline)
                }

                Spacer()
            }
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding()

            Text("Items").font(.title2).bold()

            List(items) { item in
                HStack {
                    Text(item.itemName)
                }
            }
            .listStyle(.plain)

            Spacer()
        }
    }
}

struct NewsItem: Identifiable {
    var id = UUID()
    let itemName: String
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
