//
//  ContentView.swift
//  Default Client
//
//  Created by Petar Dobrev on 7/12/23.
//

import SwiftUI

struct ListEntry: Identifiable {
    var id = UUID()
    let item: String
    let date: String
}

enum ResultStatus {
    case success
    case failure
}

struct ContentView: View {
    @State var showWeb = false
    @State var password = ""
    @State var centralIndex = 0
    @State private var orders: [ListEntry] = []

    var body: some View {
        ZStack {
            MainScreen(orders: $orders) {
                showWeb = true
            }
            .sheet(isPresented: $showWeb) {
//                AmazonWebView(
//                    orders: $orders,
//                    onClose: {
//                        showWeb = false
//                    },
//                    onResult: { _ in
//                        showWeb = false
//                    }
//                )

                AirBnbWebView(
                    orders: $orders,
                    onClose: {
                        showWeb = false
                    },
                    onResult: { _ in
                        showWeb = false
                    }
                )
            }
        }
    }
}

struct CardBoundsKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

struct MainScreen: View {
    @Environment(\.colorScheme)
    var colorScheme

    @Binding var orders: [ListEntry]
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
                Text("Connect with your account to fetch your latest orders and use the information in your app!"
                )
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
                Image("Amazon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30)
                    .padding()

                VStack(alignment: .leading) {
                    Button("Connect your account") {
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

            Text("Entries").font(.title2).bold()

            List(orders) { order in
                HStack {
                    Text(order.item)
                    Spacer()
                    Text("\(order.date)").frame(width: 120)
                        .font(.footnote)
                }
            }
            .listStyle(.plain)

            Spacer()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

func maskString(_ str: String) -> String {
    let endIndex = str.endIndex
    guard str.count > 4 else { return str }

    let last4 = str[str.index(endIndex, offsetBy: -4)...]
    let toBeReplaced = str[..<str.index(endIndex, offsetBy: -4)]

    let masked = toBeReplaced.map { $0 == " " ? " " : "*" }
    return (masked + [String(last4)]).joined()
}
