//
//  SATPrepWidget.swift
//  SATPrepWidget
//
//  Created by Parv Surjan on 9/26/26.
//

import WidgetKit
import SwiftUI

struct ProgressEntry: TimelineEntry {
    let date: Date
    let count: Int
    let goal: Int
}

struct SATPrepWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), count: 8, goal: DailyProgress.goal)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: Date(), count: DailyProgress.todayCount, goal: DailyProgress.goal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: Date(), count: DailyProgress.todayCount, goal: DailyProgress.goal)
        // The app also force-reloads the timeline after every answer; this is just a backstop.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SATPrepWidgetEntryView: View {
    var entry: ProgressEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        entry.goal > 0 ? min(Double(entry.count) / Double(entry.goal), 1) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "pencil.and.list.clipboard")
            } currentValueLabel: {
                Text("\(entry.count)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "satprep://practice"))

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("SAT Practice")
                    .font(.headline)
                Gauge(value: progress) {
                    Text("\(entry.count)/\(entry.goal)")
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
            .widgetURL(URL(string: "satprep://practice"))

        default:
            VStack(spacing: 4) {
                Text("\(entry.count)/\(entry.goal)")
                    .font(.title2.bold())
                Text("questions today")
                    .font(.caption)
            }
            .widgetURL(URL(string: "satprep://practice"))
        }
    }
}

struct SATPrepWidget: Widget {
    let kind: String = "SATPrepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SATPrepWidgetProvider()) { entry in
            SATPrepWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Daily Questions")
        .description("Track today's progress toward your practice goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
