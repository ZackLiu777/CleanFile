import SwiftUI

// MARK: - 1. 方案 E：微光圆环与数显 (Glass Ring)
struct RingProgressView: View {
    var progress: Double // 0.0 ... 1.0
    var size: CGFloat = 44
    var strokeWidth: CGFloat = 4.5
    
    var body: some View {
        ZStack {
            // 背景底环
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: strokeWidth)
            
            // 进度环
            Circle()
                .trim(from: 0, to: min(CGFloat(progress), 1.0))
                .stroke(
                    AngularGradient(
                        colors: [Color(hex: "FF7B7B"), Color(hex: "FFB366"), Color(hex: "FF7B7B")],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            
            // 百分比文字
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 2. 方案 F：动态水韵波浪进度条 (Liquid Wave)
struct WaveProgressView: View {
    var progress: Double // 0.0 ... 1.0
    var height: CGFloat = 12
    @State private var waveOffset: Angle = .zero
    
    var body: some View {
        GeometryReader { geometry in
            let filledWidth = max(0, geometry.size.width * CGFloat(progress))
            
            ZStack(alignment: .leading) {
                // 背景轨道
                Capsule()
                    .fill(Color.black.opacity(0.06))
                
                // 波浪填充区域
                ZStack {
                    WaveShape(offset: waveOffset, waveHeight: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFA07A"), Color(hex: "FF6B6B")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(width: filledWidth)
                .clipShape(Capsule())
                .shadow(color: Color(hex: "FF6B6B").opacity(0.3), radius: 3, y: 1)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                waveOffset = .degrees(360)
            }
        }
    }
}

// 正弦波浪 Shape
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
        path.closeSubpath() // 修复此行：将 close() 修改为 closeSubpath()
        
        return path
    }
}

// MARK: - 3. 方案 G：流线悬浮胶囊 (Floating Capsule Badge)
struct CapsuleProgressBadge: View {
    var title: String
    var progress: Double // 0.0 ... 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 胶囊背景
                Capsule()
                    .fill(Color.black.opacity(0.05))
                
                // 进度填充层
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF8E53").opacity(0.25), Color(hex: "FE6B8B").opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(progress))
                
                // 内部文字排版
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "E65100"))
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(height: 32)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }
}

// MARK: - 4. 方案 H：点阵像素/粒度指示器 (Dot Matrix Tracker)
struct DotMatrixProgressBar: View {
    var progress: Double // 0.0 ... 1.0
    var totalDots: Int = 12
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalDots, id: \.self) { index in
                let threshold = Double(index + 1) / Double(totalDots)
                let isActive = progress >= threshold
                
                Circle()
                    .fill(
                        isActive
                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.black.opacity(0.08))
                    )
                    .frame(height: 8)
                    .scaleEffect(isActive ? 1.1 : 0.9)
                    .shadow(color: isActive ? Color.orange.opacity(0.4) : .clear, radius: 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.02), value: progress)
            }
        }
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

// MARK: - 对比预览 (#Preview)
#Preview("全新范式进度组件对比") {
    VStack(spacing: 24) {
        
        // 1. 圆环数显方案卡片
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("正在整理相似照片...")
                    .font(.system(size: 15, weight: .bold))
                Text("已分析 119 / 987")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            RingProgressView(progress: 0.35, size: 48)
        }
        .padding()
        .background(Color.white.opacity(0.65))
        .cornerRadius(18)
        
        // 2. 动态波浪水韵卡片
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("视频压缩中")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("68%")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.orange)
            }
            WaveProgressView(progress: 0.68, height: 12)
        }
        .padding()
        .background(Color.white.opacity(0.65))
        .cornerRadius(18)
        
        // 3. 流线胶囊整合方案卡片
        VStack(alignment: .leading, spacing: 10) {
            Text("后台任务")
                .font(.caption)
                .foregroundColor(.secondary)
            
            CapsuleProgressBadge(title: "正在导入 · 1个视频", progress: 0.42)
        }
        .padding()
        .background(Color.white.opacity(0.65))
        .cornerRadius(18)
        
        // 4. 点阵像素指示器卡片
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("分析照片特征")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("75%")
                    .font(.caption)
                    .monospaced()
                    .foregroundColor(.secondary)
            }
            DotMatrixProgressBar(progress: 0.75, totalDots: 14)
        }
        .padding()
        .background(Color.white.opacity(0.65))
        .cornerRadius(18)
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
