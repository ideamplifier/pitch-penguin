import SwiftUI

struct SimpleTunerView: View {
    @StateObject private var tuner = SimpleTuner()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Simple Tuner")
                .font(.largeTitle)
                .padding()
            
            // 노트 표시
            Text(tuner.note)
                .font(.system(size: 72, weight: .bold))
                .frame(height: 100)
            
            // 주파수 표시
            Text(String(format: "%.1f Hz", tuner.frequency))
                .font(.title2)
                .foregroundColor(.secondary)
            
            // Cents 미터
            ZStack {
                // 배경 스케일
                HStack(spacing: 0) {
                    ForEach(-5...5, id: \.self) { i in
                        Rectangle()
                            .fill(i == 0 ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 2, height: i % 5 == 0 ? 40 : 20)
                            .frame(width: 30)
                    }
                }
                
                // 바늘
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 60)
                    .offset(x: CGFloat(tuner.cents * 3)) // 1 cent = 3 points
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tuner.cents)
            }
            .frame(height: 60)
            .clipped()
            
            // Cents 수치
            Text(String(format: "%+.0f cents", tuner.cents))
                .font(.title3)
                .foregroundColor(abs(tuner.cents) < 5 ? .green : .orange)
            
            // 시작/정지 버튼
            HStack(spacing: 40) {
                Button("Start") {
                    tuner.start()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Stop") {
                    tuner.stop()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .padding()
        .onAppear {
            tuner.start()
        }
        .onDisappear {
            tuner.stop()
        }
    }
}