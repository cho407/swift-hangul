#if canImport(SwiftUI)
import SwiftUI

@available(iOS 15.0, macOS 12.0, *)
private struct HangulSearchableModifier<Item>: ViewModifier {
    @Binding var text: String
    @ObservedObject var controller: HangulSearchController<Item>
    let prompt: Text?

    func body(content: Content) -> some View {
        bindQueryChange(
            searchable(content: content)
                .onAppear {
                    controller.submit(text, immediate: true)
                }
        )
    }

    @ViewBuilder
    private func searchable(content: Content) -> some View {
        if let prompt {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content.searchable(text: $text)
        }
    }

    @ViewBuilder
    private func bindQueryChange<V: View>(_ view: V) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            view.onChange(of: text) { _, newValue in
                controller.submit(newValue)
            }
        } else {
            view.onChange(of: text) { newValue in
                controller.submit(newValue)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct HangulSearchableSuggestionsModifier<Item, Suggestions: View>: ViewModifier {
    @Binding var text: String
    @ObservedObject var controller: HangulSearchController<Item>
    let prompt: Text?
    let suggestions: ([Item]) -> Suggestions

    func body(content: Content) -> some View {
        bindQueryChange(
            searchable(content: content)
                .onAppear {
                    controller.submit(text, immediate: true)
                }
        )
    }

    @ViewBuilder
    private func searchable(content: Content) -> some View {
        if let prompt {
            content.searchable(text: $text, prompt: prompt) {
                suggestions(controller.results)
            }
        } else {
            content.searchable(text: $text) {
                suggestions(controller.results)
            }
        }
    }

    @ViewBuilder
    private func bindQueryChange<V: View>(_ view: V) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            view.onChange(of: text) { _, newValue in
                controller.submit(newValue)
            }
        } else {
            view.onChange(of: text) { newValue in
                controller.submit(newValue)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
public extension View {
    func hangulSearchable<Item>(
        text: Binding<String>,
        controller: HangulSearchController<Item>,
        prompt: Text? = nil
    ) -> some View {
        modifier(
            HangulSearchableModifier(
                text: text,
                controller: controller,
                prompt: prompt
            )
        )
    }

    func hangulSearchable<Item, Suggestions: View>(
        text: Binding<String>,
        controller: HangulSearchController<Item>,
        prompt: Text? = nil,
        @ViewBuilder suggestions: @escaping ([Item]) -> Suggestions
    ) -> some View {
        modifier(
            HangulSearchableSuggestionsModifier(
                text: text,
                controller: controller,
                prompt: prompt,
                suggestions: suggestions
            )
        )
    }
}
#endif
