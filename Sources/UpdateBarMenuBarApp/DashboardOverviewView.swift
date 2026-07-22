#if os(macOS)
    import Accessibility
    import Charts
    import Foundation
    import SwiftUI
    import UpdateBarMenuBar

    struct DashboardOverviewView: View {
        var summary: DashboardSummary

        private let presentationModel = DashboardPresentationModel()
        private let metricColumns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        var body: some View {
            let metrics = presentationModel.overviewMetrics(for: summary)

            VStack(alignment: .leading, spacing: 18) {
                Text("Overview")
                    .font(.title2.weight(.semibold))

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                    ForEach(metrics.indices, id: \.self) { index in
                        tile(metrics[index])
                    }
                }

                ZStack {
                    Chart(summary.updatesPerDay, id: \.day) { bucket in
                        BarMark(
                            x: .value("Day", bucket.day, unit: .day),
                            y: .value("Updates", bucket.count)
                        )
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3))
                    }
                    .chartXScale(
                        range: .plotDimension(startPadding: 20, endPadding: 20)
                    )
                    .accessibilityChartDescriptor(
                        UpdatesChartDescriptor(buckets: summary.updatesPerDay)
                    )

                    if let chartEmptyMessage {
                        Text(chartEmptyMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }
            .padding(20)
            .frame(minWidth: 620, minHeight: 420, alignment: .topLeading)
        }

        private var totalUpdates: Int {
            summary.updatesPerDay.reduce(0) { $0 + $1.count }
        }

        private var chartEmptyMessage: String? {
            if summary.updatesPerDay.isEmpty {
                return "No update history available"
            }
            if totalUpdates == 0 {
                return "No updates in the last 4 weeks"
            }
            return nil
        }

        private func tile(_ metric: DashboardMetricPresentation) -> some View {
            HStack(spacing: 8) {
                Image(systemName: metric.iconName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(metric.visibleValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                .quaternary.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .help(metric.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metric.accessibilityLabel)
            .accessibilityValue(metric.accessibilityValue)
        }
    }

    private struct UpdatesChartDescriptor: AXChartDescriptorRepresentable {
        var buckets: [DashboardDayCount]

        func makeChartDescriptor() -> AXChartDescriptor {
            let dateLabels = buckets.map { dateLabel($0.day) }
            let xAxis = AXCategoricalDataAxisDescriptor(
                title: "Date",
                categoryOrder: dateLabels
            )
            let maximumCount = buckets.map(\.count).max() ?? 0
            let yAxis = AXNumericDataAxisDescriptor(
                title: "Update count",
                range: 0...Double(max(1, maximumCount)),
                gridlinePositions: []
            ) { value in
                countLabel(Int(value.rounded()))
            }
            let dataPoints = zip(buckets, dateLabels).map { bucket, dateLabel in
                AXDataPoint(
                    x: dateLabel,
                    y: Double(bucket.count),
                    label: "\(dateLabel): \(countLabel(bucket.count))"
                )
            }
            let series = AXDataSeriesDescriptor(
                name: "Daily updates",
                isContinuous: false,
                dataPoints: dataPoints
            )

            return AXChartDescriptor(
                title: "Updates in the last 4 weeks",
                summary: descriptorSummary,
                xAxis: xAxis,
                yAxis: yAxis,
                series: [series]
            )
        }

        private var descriptorSummary: String {
            guard let first = buckets.first, let last = buckets.last else {
                return "No daily update data is available."
            }
            let firstDate = dateLabel(first.day)
            let lastDate = dateLabel(last.day)
            return "Daily update counts from \(firstDate) through \(lastDate)."
        }

        private func dateLabel(_ date: Date) -> String {
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }

        private func countLabel(_ count: Int) -> String {
            let noun = count == 1 ? "update" : "updates"
            return "\(count) \(noun)"
        }
    }
#endif
