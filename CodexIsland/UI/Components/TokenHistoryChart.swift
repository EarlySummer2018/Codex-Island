import Charts
import SwiftUI

struct TokenHistoryChart: View {
    let history: [TokenSnapshot]

    private var recentHistory: [(offset: Int, snapshot: TokenSnapshot)] {
        Array(history.suffix(20).enumerated()).map { index, snapshot in
            (offset: index + 1, snapshot: snapshot)
        }
    }

    var body: some View {
        Chart {
            ForEach(recentHistory, id: \.snapshot.id) { item in
                LineMark(
                    x: .value("Turn", item.offset),
                    y: .value("Output", item.snapshot.deltaOutput)
                )
                .foregroundStyle(TokenColors.output)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Turn", item.offset),
                    y: .value("Output", item.snapshot.deltaOutput)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            TokenColors.output.opacity(0.22),
                            TokenColors.output.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(Color.clear)
        }
    }
}
