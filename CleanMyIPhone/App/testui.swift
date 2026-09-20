import SwiftUI

// MARK: - 方案一：液态波浪胶囊轨道 (Dynamic Fluid Wave Track)
struct DynamicWaveSlider: View {
    @Binding var value: Double // 0.0 ... 1.0
    
    @State private var waveOffset: Angle = .zero
    @State private var isDragging: Bool = false
    @State private var waveHeight: CGFloat = 2.5
    
    var body: some View {
        VStack(spacing: 8) {
            // 顶部信息展示
            HStack {
                Text("压缩质量")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                Spacer()
                Text(qualityLabel(for: value))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "FF6B6B"))
            }
            
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 20 // 较宽的液态容器
                let filledWidth = max(height, CGFloat(value) * width)
                
                ZStack(alignment: .leading) {
                    // 1. 底轨道（微光透明容器）
                    Capsule()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        )
                        .frame(height: height)
                    
                    // 2. 动态波浪液体填充（条状本身在流动）
                    ZStack(alignment: .trailing) {
                        WaveShape(offset: waveOffset, waveHeight: waveHeight)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "FFB366"),
                                        Color(hex: "FF7B7B"),
                                        Color(hex: "FE6B8B")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .hueRotation(.degrees(value * 20)) // 随质量高低有微弱色相偏移
                        
                        // 液体右侧高光水滴触点
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color(hex: "FF7B7B").opacity(0.5), radius: 4, y: 1)
                            .frame(width: height - 4, height: height - 4)
                            .padding(.trailing, 2)
                    }
                    .frame(width: filledWidth, height: height)
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "FF7B7B").opacity(0.3), radius: 6, y: 3)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    isDragging = true
                                    waveHeight = 4.5 // 拖动时水波变大
                                }
                            }
                            let raw = min(max(0, gesture.location.x / width), 1.0)
                            self.value = Double(raw)
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                isDragging = false
                                waveHeight = 2.5 // 松手后水波平缓
                            }
                        }
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 36)
            
            // 底部节点
            HStack {
                Text("体积更小")
                Spacer()
                Text("平衡")
                Spacer()
                Text("无损质量")
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                waveOffset = .degrees(360)
            }
        }
    }
    
    private func qualityLabel(for val: Double) -> String {
        return "\(Int(val * 100))%"
    }
}

// MARK: - 方案二：磁吸分段流光粒子轨道 (Magnetic Segment Stream)
struct SegmentedStreamSlider: View {
    @Binding var value: Double // 0.0 ... 1.0
    let totalSegments: Int = 10
    
    @State private var streamOffset: CGFloat = -0.3
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("压缩质量")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "E65100"))
            }
            
            GeometryReader { geometry in
                let width = geometry.size.width
                
                HStack(spacing: 4) {
                    ForEach(0..<totalSegments, id: \.self) { index in
                        let threshold = Double(index + 1) / Double(totalSegments)
                        let isActive = value >= threshold - (1.0 / Double(totalSegments) / 2)
                        
                        GeometryReader { itemGeo in
                            ZStack {
                                // 基础块背景
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        isActive
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [Color(hex: "FFA07A"), Color(hex: "FF6B6B")],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                          )
                                        : AnyShapeStyle(Color.black.opacity(0.06))
                                    )
                                
                                // 激活块内部的微流光动效
                                if isActive {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, Color.white.opacity(0.4), .clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .offset(x: streamOffset * itemGeo.size.width)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(height: 14)
                        .scaleEffect(y: isActive ? 1.15 : 0.95)
                        .shadow(color: isActive ? Color(hex: "FF6B6B").opacity(0.35) : .clear, radius: 3, y: 1.5)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let raw = min(max(0, gesture.location.x / width), 1.0)
                            self.value = Double(raw)
                        }
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 36)
            
            HStack {
                Text("体积更小")
                Spacer()
                Text("平衡")
                Spacer()
                Text("质量最佳")
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                streamOffset = 1.2
            }
        }
    }
}

// MARK: - 波浪 Shape
struct WaveShape: Shape {
    var offset: Angle
    var waveHeight: CGFloat
    
    var animatableData: Double {
        get { offset.degrees }
        set { offset = .degrees(newValue) }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: 0, y: height))
        
        for x in stride(from: 0, through: width, by: 2) {
            let relativeX = x / width
            let sine = sin(relativeX * .pi * 4 + offset.radians)
            let y = height / 2 + CGFloat(sine) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Color 辅助扩展
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - 预览
#Preview("全新动态轨道方案") {
    struct PreviewWrapper: View {
        @State private var quality1: Double = 0.85
        @State private var quality2: Double = 0.70
        
        var body: some View {
            VStack(spacing: 24) {
                
                // 1. 液态波浪胶囊轨道
                VStack {
                    DynamicWaveSlider(value: $quality1)
                }
                .padding(18)
                .background(Color.white.opacity(0.65))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 10, y: 5)
                
                // 2. 磁吸分段流光粒子轨道
                VStack {
                    SegmentedStreamSlider(value: $quality2)
                }
                .padding(18)
                .background(Color.white.opacity(0.65))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 10, y: 5)
                
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(hex: "E6F4EA"), Color(hex: "F3E5F5"), Color(hex: "E8EAF6")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    return PreviewWrapper()
}
