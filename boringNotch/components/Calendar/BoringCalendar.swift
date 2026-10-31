//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import SwiftUI

/// Semaine de la date choisie, ‹ › pour changer de semaine.
struct WeekStrip: View {
    @Binding var selectedDate: Date
    private let cal = Calendar.current

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            shift(-7, icon: "chevron.left")
            ForEach(days, id: \.self) { day in
                let selected = cal.isDate(day, inSameDayAs: selectedDate)
                let today = cal.isDateInToday(day)
                Button { selectedDate = day } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(size: 11, weight: selected || today ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(selected ? .white : today ? Color.effectiveAccent : Color(white: 0.75))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(selected ? Color.effectiveAccent : .clear))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            shift(7, icon: "chevron.right")
        }
    }

    private func shift(_ days: Int, icon: String) -> some View {
        Button {
            if let d = cal.date(byAdding: .day, value: days, to: selectedDate) { selectedDate = d }
        } label: {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
                .frame(width: 12, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        // Agenda : date en grand + semaine à gauche, événements à droite.
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Button { selectedDate = .now } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.effectiveAccent)
                        Text(selectedDate.formatted(.dateTime.day()))
                            .font(.system(size: 34, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                WeekStrip(selectedDate: $selectedDate)
            }
            .frame(width: 190)

            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events
            )
            Group {
                if filteredEvents.isEmpty {
                    EmptyEventsView(selectedDate: selectedDate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EventListView(events: calendarManager.events)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date
    
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !Defaults[.hideCompletedReminders]
                }
            }
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        if let url = event.calendarAppURL() {
                            openURL(url)
                        }
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)  // Ensure the toggle is always fully opaque
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if event.isAllDay {
                            Text("All-day")
                                .foregroundColor(Color(white: 0.65))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .trailing)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? 2 : 1)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.5 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                // Inner fill
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

#Preview {
    CalendarView()
        .frame(width: 640, height: 140)
        .background(.black)
        .environmentObject(BoringViewModel())
}
