import SwiftUI

// MARK: - DialView メインのビュー
struct DialView<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Hashable {
  // (プロパティ定義は変更なし)
  private let data: Data
  private let content: (Data.Element) -> Content
  @Binding private var selection: Data.Element
  private let configuration: DialConfiguration
  private let isDebug: Bool = false

  @State private var rotationAngle: Angle = .zero
  @State private var lastDragAngle: Angle = .zero

  // (Initializerは変更なし)
  init(
    data: Data,
    selection: Binding<Data.Element>,
    configuration: DialConfiguration = DialConfiguration(),
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self._selection = selection
    self.content = content
    self.configuration = configuration
  }

  // (BodyとSubviewsは変更なし)
  var body: some View {
    VStack {
      if isDebug,
        let currentIndex = data.firstIndex(of: selection)
      {
        let indexNumber = data.distance(from: data.startIndex, to: currentIndex)
        Text("選択中: \(String(describing: selection)) (\(indexNumber))")
          .font(.headline)
          .padding()
      }

      ZStack(alignment: .top) {
        dial
        selectionIndicator
      }
      .frame(width: configuration.radius * 2, height: configuration.radius * 2)
      .contentShape(Circle())
      .padding()
    }
    .onAppear(perform: setupInitialRotation)
  }

  private var dial: some View {
    ZStack {
      ForEach(Array(data.enumerated()), id: \.element) { index, element in
        content(element)
          .offset(y: -configuration.radius)
          .rotationEffect(rotationAngleForIndex(index))
      }
    }
    .frame(width: configuration.radius * 2, height: configuration.radius * 2)
    .rotationEffect(rotationAngle)
    .gesture(dragGesture)
  }

  private var selectionIndicator: some View {
    Image(systemName: "triangle.fill")
      .font(.caption)
      .foregroundColor(.red)
      .rotationEffect(.degrees(180))
      .offset(y: -configuration.indicatorOffset)
  }

  // MARK: - Gestures (onChanged内を修正)

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let dragAngle = angle(for: value.location)

        if lastDragAngle != .zero {
          // 【修正点】角度の差分を計算し、360度の境界をまたぐ際のジャンプを補正する
          var diff = dragAngle - lastDragAngle
          if diff.degrees > 180 {
            diff.degrees -= 360
          } else if diff.degrees < -180 {
            diff.degrees += 360
          }

          rotationAngle += diff
        }

        lastDragAngle = dragAngle
        updateSelectionOnDrag()
      }
      .onEnded { _ in
        lastDragAngle = .zero
        snapToNearestTick()
      }
  }

  // (Helper Methods は変更なし)
  private var anglePerTick: Angle {
    .degrees(360.0 / Double(data.count))
  }

  private func rotationAngleForIndex(_ index: Int) -> Angle {
    .degrees(Double(index) * anglePerTick.degrees)
  }

  private func angle(for point: CGPoint) -> Angle {
    let centerX = configuration.radius
    let centerY = configuration.radius
    let dx = point.x - centerX
    let dy = point.y - centerY
    let radians = atan2(dy, dx)
    return Angle(radians: radians) + .degrees(90)
  }

  private func snapToNearestTick() {
    let selectionAngle = -rotationAngle.degrees
    let normalizedAngle = selectionAngle.truncatingRemainder(dividingBy: 360)
    let positiveAngle =
      normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle
    let nearestIndex = Int(round(positiveAngle / anglePerTick.degrees))

    let baseTargetAngle = -Double(nearestIndex) * anglePerTick.degrees

    let currentRevolution = round(rotationAngle.degrees / 360.0)

    let targetCandidates = [
      baseTargetAngle + 360.0 * (currentRevolution - 1),
      baseTargetAngle + 360.0 * currentRevolution,
      baseTargetAngle + 360.0 * (currentRevolution + 1),
    ]

    let targetAngle =
      targetCandidates.min(by: {
        abs($0 - rotationAngle.degrees) < abs($1 - rotationAngle.degrees)
      }) ?? 0

    withAnimation(
      .spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0)
    ) {
      rotationAngle = .degrees(targetAngle)
    }

    updateSelectionAfterSnap(at: nearestIndex)
  }

  /// ドラッグ中の選択値更新 + 軽いフィードバック
  private func updateSelectionOnDrag() {
    let selectionAngle = -rotationAngle.degrees
    let normalizedAngle = selectionAngle.truncatingRemainder(dividingBy: 360)
    let positiveAngle =
      normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle
    let selectedIndex =
      Int(round(positiveAngle / anglePerTick.degrees)) % data.count

    if let index = data.index(
      data.startIndex,
      offsetBy: selectedIndex,
      limitedBy: data.endIndex
    ),
      index != data.endIndex
    {
      let newSelection = data[index]
      if selection != newSelection {
        selection = newSelection
        // 項目が切り替わるたびに軽いフィードバックを生成
        generateTickHapticFeedback()
      }
    }
  }

  /// スナップ完了後の選択値更新 + 確定フィードバック
  private func updateSelectionAfterSnap(at index: Int) {
    let wrappedIndex = index % data.count
    if let newIndex = data.index(
      data.startIndex,
      offsetBy: wrappedIndex,
      limitedBy: data.endIndex
    ),
      newIndex != data.endIndex
    {
      let newSelection = data[newIndex]
      selection = newSelection
      // 値が確定したことを示す、より強いフィードバックを生成
      generateSelectionHapticFeedback()
    }
  }

  // MARK: Haptic Feedback

  /// ドラッグ中に目盛りが切り替わった際の軽いフィードバック
  private func generateTickHapticFeedback() {
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    feedbackGenerator.prepare()
    feedbackGenerator.impactOccurred()
  }

  /// スナップして値が確定した際の、より強いフィードバック
  private func generateSelectionHapticFeedback() {
    let feedbackGenerator = UINotificationFeedbackGenerator()
    feedbackGenerator.prepare()
    feedbackGenerator.notificationOccurred(.success)
  }

  private func setupInitialRotation() {
    if let initialIndex = data.firstIndex(of: selection) {
      let index = data.distance(from: data.startIndex, to: initialIndex)
      let angle = -rotationAngleForIndex(index)
      rotationAngle = angle
    }
  }
}

// MARK: - DialConfiguration ダイヤルの設定を保持する構造体
struct DialConfiguration {
  let radius: CGFloat
  let indicatorOffset: CGFloat

  init(radius: CGFloat = 80, indicatorOffset: CGFloat = 20) {
    self.radius = radius
    self.indicatorOffset = indicatorOffset
  }
}
