import AVFoundation
import SwiftUI

struct ISOConfigurationView: View {
  let min: Float
  let max: Float
  @State var value: Float?
  var step: Float = 100
  var completion: (_ value: Float?) -> Void

  // maxも選択肢に含める
  var allValues: [Float] {
    var values = Array(stride(from: min, to: max, by: step))
    if values.last != max { values.append(max) }
    return values
  }

  var body: some View {
    VStack {
      GeometryReader { geometoryProxy in
        ZStack(alignment: .center) {
          ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 24) {
                ForEach(allValues, id: \.self) { iso in
                  VStack(spacing: 8) {
                    Rectangle()
                      .fill(value == iso ? Color.yellow : Color.white)
                      .frame(width: 2, height: 20)
                    Text("\(Int(iso))")
                      .font(.caption2)
                      .foregroundColor(value == iso ? .yellow : .white)
                  }
                  .frame(width: 40)
                  .contentShape(Rectangle())  // タップしやすく
                }
              }
              .padding(.horizontal, geometoryProxy.size.width / 2 - 20)
              .scrollTargetLayout()
            }
            .padding(.vertical, 4)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $value, anchor: .center)
            .onAppear {
              // 初期選択位置へ
              scrollProxy.scrollTo(value, anchor: .center)
            }
          }

          Rectangle()
            .fill(.white)
            .frame(width: 2, height: 48)
        }
      }

      Button {
        completion(value)
      } label: {
        Text("Completion")
      }
      .buttonStyle(.borderedProminent)
    }
    .background(.black)
  }
}

#Preview {
  ISOConfigurationView(min: 100, max: 20000, value: 1000) { _ in }
}
