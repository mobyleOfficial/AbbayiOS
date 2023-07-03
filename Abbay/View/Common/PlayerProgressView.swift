//
//  ProgressView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import SwiftUI

struct PlayerProgressView: View {
    // MARK: - Properties
    @Binding
    var currentTime: Double
    var totalTime: Double
    var tint: Color = ColorConstants.malachite.value
    var onStartUpdate: VoidCallback?
    var onUpdate: ((Double) -> Void)?
    var onFinishUpdate: ((Double) -> Void)?

    // MARK: - States
    @State
    private var offset: CGFloat = 0
    @State
    private var isDragging = false

    // MARK: - Body
    var body: some View {
        VStack {
            GeometryReader { geometry in
                let viewWidth = geometry.frame(in: .local).width
                let viewHeight = geometry.frame(in: .local).height
                ZStack(alignment: .leading) {
                    ProgressView(value: currentTime, total: totalTime)
                        .tint(tint)
                        .progressViewStyle(.linear)
                    Circle()
                        .fill(
                            isDragging ?
                            ColorConstants.malachite.value
                            : ColorConstants.clear.value
                        )
                        .frame(width: SpaceConstants.sx12.value)
                        .offset(.init(width: offset, height: .zero))
                        .onChange(of: currentTime) { newTime in
                            offset = (newTime * viewWidth) / totalTime
                        }
                }
                .background {
                    ColorConstants.clear.value
                        .frame(height: viewHeight * 4)
                        .onTouch(limitToBounds: false) { _ in
                            onStartUpdate?()
                        } onTouchesMoved: { location in
                            let pos = location.x
                            guard 0...viewWidth ~= pos else { return }
                            currentTime = (pos * totalTime) / viewWidth
                            isDragging = true
                            onUpdate?(currentTime)
                        } onTouchesEnded: { _ in
                            isDragging = false
                            onFinishUpdate?(currentTime)
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(currentTime.timestamp)
                Spacer()
                Text(totalTime.timestamp)
            }
        }
    }
}

// MARK: - Preview
struct ProgressView_Previews: PreviewProvider {
    private struct ProgressPreview: View {
        @State
        var currentTime: Double = 1500

        var body: some View {
            PlayerProgressView(
                currentTime: $currentTime,
                totalTime: 3000
            )
            .padding(SpaceConstants.sx16.value)
        }
    }

    static var previews: some View {
        ProgressPreview()
    }
}
