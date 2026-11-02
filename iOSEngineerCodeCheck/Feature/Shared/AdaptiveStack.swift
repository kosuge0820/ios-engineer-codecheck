import SwiftUI

/// 通常は横並び、アクセシビリティ文字サイズでは縦並びにするスタック。
///
/// 横並びのまま大きい文字にすると単語の途中で折り返されるため、`dynamicTypeSize.isAccessibilitySize` で切り替える。
/// この切り替えはここだけが持つ。
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 横並びのときの揃え方と間隔。
    var verticalAlignment: VerticalAlignment = .center
    var horizontalSpacing: CGFloat? = nil
    /// 縦並びのときの揃え方と間隔。
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalSpacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: verticalSpacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: horizontalSpacing))
        layout {
            content()
        }
    }
}
