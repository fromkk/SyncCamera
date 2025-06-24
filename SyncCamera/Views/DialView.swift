import SwiftUI

struct DialView<Value: RandomAccessCollection, Content: View>: View
where Value.Element: Hashable {
  private let allValue: Value
  private let content: (Value.Element) -> Content
  @Binding private var selection: Value.Element?
  private let configuration: DialConfiguration
  private let isDebug: Bool = false

  @State private var rotationAngle: Angle = .zero
  @State private var lastDragAngle: Angle = .zero

  init(
    allValue: Value,
    selection: Binding<Value.Element?>,
    configuration: DialConfiguration = DialConfiguration(),
    @ViewBuilder content: @escaping (Value.Element) -> Content
  ) {
    self.allValue = allValue
    self._selection = selection
    self.content = content
    self.configuration = configuration
  }

  var body: some View {
    VStack {
      if isDebug,
        let selection,
        let currentIndex = allValue.firstIndex(of: selection)
      {
        let indexNumber = allValue.distance(
          from: allValue.startIndex,
          to: currentIndex
        )
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
    // selection の変更を監視し、rotationAngle を更新
    .onChange(of: selection) { _, newSelection in
      guard let newSelection = newSelection else { return }
      if let index = allValue.firstIndex(of: newSelection) {
        let initialIndex = allValue.distance(
          from: allValue.startIndex,
          to: index
        )
        let targetAngle = -rotationAngleForIndex(initialIndex)

        // 現在の回転角度と目標角度の差を考慮して、最も近い回転量でアニメーションさせる
        // このロジックはsnapToNearestTick()でのtargetAngle計算ロジックに似ているが、
        // onChangeではドラッグ中の状態を考慮しないため、よりシンプルになる
        let currentDegrees = rotationAngle.degrees
        let targetDegrees = targetAngle.degrees

        let diff = (targetDegrees - currentDegrees).truncatingRemainder(
          dividingBy: 360
        )
        let adjustedTarget: Double
        if diff > 180 {
          adjustedTarget = targetDegrees - 360
        } else if diff < -180 {
          adjustedTarget = targetDegrees + 360
        } else {
          adjustedTarget = targetDegrees
        }

        withAnimation(
          .spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0)
        ) {
          rotationAngle = .degrees(adjustedTarget)
        }
      }
    }
  }

  private var dial: some View {
    ZStack {
      ForEach(Array(allValue.enumerated()), id: \.element) { index, element in
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

  // MARK: - Gestures

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let dragAngle = angle(for: value.location)

        if lastDragAngle != .zero {
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

  // MARK: - Helper Methods

  private var anglePerTick: Angle {
    .degrees(360.0 / Double(allValue.count))
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
      Int(round(positiveAngle / anglePerTick.degrees)) % allValue.count

    if let index = allValue.index(
      allValue.startIndex,
      offsetBy: selectedIndex,
      limitedBy: allValue.endIndex
    ),
      index != allValue.endIndex
    {
      let newSelection = allValue[index]
      if selection != newSelection {
        selection = newSelection
        // 項目が切り替わるたびに軽いフィードバックを生成
        generateTickHapticFeedback()
      }
    }
  }

  /// スナップ完了後の選択値更新 + 確定フィードバック
  private func updateSelectionAfterSnap(at index: Int) {
    let wrappedIndex = index % allValue.count
    if let newIndex = allValue.index(
      allValue.startIndex,
      offsetBy: wrappedIndex,
      limitedBy: allValue.endIndex
    ),
      newIndex != allValue.endIndex
    {
      let newSelection = allValue[newIndex]
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
    if let selection, let initialIndex = allValue.firstIndex(of: selection) {
      let index = allValue.distance(from: allValue.startIndex, to: initialIndex)
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
