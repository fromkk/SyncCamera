import SwiftUI

struct SlideDialView<Value: Hashable & CustomStringConvertible>: View {
  let allValues: [Value]
  @Binding var selection: Value?
  init(allValues: [Value], selection: Binding<Value?>) {
    self.allValues = allValues
    self._selection = selection
  }

  var body: some View {
    VStack {
      GeometryReader { geometryProxy in
        ZStack(alignment: .center) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
              ForEach(allValues, id: \.self) { currentValue in
                VStack(spacing: 8) {
                  Rectangle()
                    .fill(selection == currentValue ? Color.yellow : Color.white)
                    .frame(width: 2, height: 20)
                  Text(currentValue.description)
                    .font(.caption2)
                    .foregroundColor(selection == currentValue ? .yellow : .white)
                }
                .frame(width: 48)
                .contentShape(Rectangle())
              }
            }
            .scrollTargetLayout()
          }
          .contentMargins(
            .horizontal,
            geometryProxy.size.width / 2 - 24,
            for: .scrollContent
          )
          .scrollTargetBehavior(.viewAligned)
          .scrollPosition(id: $selection, anchor: .center)

          // 中央のインジケーター
          Rectangle()
            .fill(Color.yellow)
            .frame(width: 2, height: 48)
            .allowsHitTesting(false)

          LinearGradient(
            gradient: Gradient(colors: [.black, .clear, .black]),
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(maxWidth: .infinity)
          .ignoresSafeArea()
          .allowsHitTesting(false)  // タップに干渉しないように
        }
      }
      .frame(height: 80)
      .onChange(of: selection) { _, _ in
        generateHapticFeedback()
      }
    }
    .background(.black)
  }

  private func generateHapticFeedback() {
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    feedbackGenerator.prepare()
    feedbackGenerator.impactOccurred()
  }
}

#Preview {
  struct PreviewContainer: View {
    @State private var selectedValue: Float? = 800.0

    private let isoValues: [Float] = [
      100, 200, 400, 800, 1600, 3200, 6400, 12800,
    ]

    var body: some View {
      VStack {
        DialView(
          allValue: isoValues,
          selection: $selectedValue
        ) { value in
          VStack(spacing: 8) {
            Rectangle()
              .fill(selectedValue == value ? Color.yellow : Color.white)
              .frame(width: 2, height: 20)
            Text(value.description)
              .font(.caption2)
              .foregroundColor(selectedValue == value ? .yellow : .white)
          }
          .frame(width: 48)
        }

        Text("親ビューで選択中の値: \(selectedValue?.description ?? "nil")")
          .foregroundColor(.white)
          .padding()

        Button("値を200に設定") {
          selectedValue = 200.0
        }
      }
      .preferredColorScheme(.dark)
    }
  }

  return PreviewContainer()
}
