import SwiftUI

/// Credits, and the mathematics the original got wrong.
struct AboutScreen: View {
    var body: some View {
        List {
            Section("The game") {
                Text("""
                Bridg-It was invented by **David Gale**, an American mathematician and economist, \
                and popularised by Martin Gardner in *Scientific American*, which is where it \
                picked up the name **the Game of Gale**.
                """)
            }
            Section("It is solved") {
                Text("""
                The first player always wins. **Oliver Gross** found the strategy: contract the \
                board graph, split what remains into two edge-disjoint spanning trees, and answer \
                every move your opponent makes with the paired edge from the other tree. You can \
                never be cut off.
                """)
                Text("""
                It is a special case of **Alfred Lehman's** 1964 result on the Shannon switching \
                game. The *Perfect* opponent here plays it, and going first it cannot be beaten — \
                which is also why it declines to promise anything when it plays second.
                """)
            }
            Section("This app") {
                Text("""
                A rewrite of a Java Swing version of the same game. The rules and the ideas behind \
                the opponents carried over; none of the code or artwork did.
                """)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
