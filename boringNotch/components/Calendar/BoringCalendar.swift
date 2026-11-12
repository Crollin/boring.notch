//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Combine
import Defaults
import SwiftUI

/// Calendrier : à gauche l'en-tête du jour et l'agenda des 7 prochains jours, à droite le mois.
struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var month = Date()              // un jour quelconque du mois affiché
    @State private var agenda: [EventModel] = []
    @State private var busyDays: Set<Date> = []     // débuts de jours ayant au moins un événement
    private let cal = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                DayHeader(date: selectedDate)
                AgendaList(events: agenda, selectedDate: selectedDate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MonthGrid(month: $month, selectedDate: $selectedDate, busyDays: busyDays)
                .frame(width: 230)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: selectedDate) { await reload() }
        .task(id: cal.dateInterval(of: .month, for: month)?.start) { await reload() }
        .onReceive(calendarManager.$events.dropFirst()) { _ in Task { await reload() } }   // changement côté Calendrier
        .onChange(of: vm.notchState) { _, _ in resetToToday() }
        .onAppear { resetToToday() }
    }

    private func resetToToday() {
        selectedDate = .now
        month = .now
    }

    private func reload() async {
        let day = cal.startOfDay(for: selectedDate)
        let agendaEnd = cal.date(byAdding: .day, value: 7, to: day)!
        let grid = cal.dateInterval(of: .month, for: month) ?? DateInterval(start: day, duration: 0)
        let from = min(day, grid.start), to = max(agendaEnd, grid.end)
        let all = EventListView.filteredEvents(events: await calendarManager.events(from: from, to: to))
        agenda = all.filter { $0.end > day && $0.start < agendaEnd }.sorted { $0.start < $1.start }
        var days = Set<Date>()
        for e in all {
            var d = cal.startOfDay(for: e.start)
            // Un événement sur plusieurs jours marque chacun d'eux (borné pour les très longues plages).
            while d < e.end && days.count < 400 { days.insert(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
            if e.end <= e.start { days.insert(cal.startOfDay(for: e.start)) }
        }
        busyDays = days
    }
}

/// « LUN. 2 S45 » : jour de la semaine (accent), numéro, semaine ISO. Clic : ouvre Calendrier.
private struct DayHeader: View {
    let date: Date

    var body: some View {
        Button { openInCalendarApp(date) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased())
                    .foregroundStyle(Color.calendarAccent)
                Text(date.formatted(.dateTime.day()))
                    .foregroundStyle(.white)
                Text("S\(Calendar(identifier: .iso8601).component(.weekOfYear, from: date))")
                    .foregroundStyle(Color.calendarAccent.opacity(0.6))
            }
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir dans Calendrier")
    }
}

/// Événements groupés par jour ; le jour choisi n'a pas d'en-tête (c'est celui du haut).
private struct AgendaList: View {
    let events: [EventModel]
    let selectedDate: Date
    @Default(.autoScrollToNextEvent) private var autoScroll
    private let cal = Calendar.current

    private var groups: [(day: Date, events: [EventModel])] {
        let first = cal.startOfDay(for: selectedDate)
        var byDay: [Date: [EventModel]] = [:]
        for e in events { byDay[max(cal.startOfDay(for: e.start), first), default: []].append(e) }
        return byDay.keys.sorted().map { (day: $0, events: byDay[$0]!) }
    }

    var body: some View {
        let first = cal.startOfDay(for: selectedDate)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if groups.first?.day != first {
                        Text(cal.isDateInToday(first) ? "Rien aujourd'hui" : "Aucun événement")
                            .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                            .padding(.bottom, 4)
                    }
                    ForEach(groups, id: \.day) { group in
                        if group.day != first {
                            Text(group.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                                .padding(.top, 5)
                        }
                        ForEach(group.events) { EventCard(event: $0).id($0.id) }
                    }
                    if events.isEmpty {
                        Text("Semaine libre").font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .onAppear { scrollToNext(proxy) }
            .onChange(of: events) { _, _ in scrollToNext(proxy) }
        }
    }

    /// Amène le prochain événement non terminé en haut (réglage « défiler jusqu'au prochain événement »).
    private func scrollToNext(_ proxy: ScrollViewProxy) {
        guard autoScroll, let next = events.first(where: { !$0.isAllDay && $0.end > .now }) else { return }
        withTransaction(Transaction(animation: nil)) { proxy.scrollTo(next.id, anchor: .top) }
    }
}

/// Mois en grille : aujourd'hui en pastille pleine, jour choisi cerclé, point sous les jours occupés.
private struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selectedDate: Date
    let busyDays: Set<Date>
    private let cal = Calendar.current

    private var cells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        return Array(s[(cal.firstWeekday - 1)...] + s[..<(cal.firstWeekday - 1)])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                shift(-1, "chevron.left")
                shift(1, "chevron.right")
                Spacer()
                Button { month = .now; selectedDate = .now } label: {
                    Text(monthTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.calendarAccent)
                }
                .buttonStyle(.plain)
                .help("Revenir à aujourd'hui")
            }
            .frame(height: 15)

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { i, s in
                    Text(s.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: isWeekendColumn(i) ? 0.35 : 0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)
            // La hauteur disponible varie (notch, onglets) : la taille des chiffres en découle, sans chevauchement.
            let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
            let weeks = padded.count / 7
            GeometryReader { geo in
                let rowH = geo.size.height / CGFloat(max(weeks, 1))
                VStack(spacing: 0) {
                    ForEach(0..<weeks, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { i in
                                if let day = padded[w * 7 + i] { dayCell(day, rowHeight: rowH) } else { Color.clear.frame(maxWidth: .infinity) }
                            }
                        }
                        .frame(height: rowH)
                    }
                }
            }
        }
    }

    /// « NOV » ; l'année n'apparaît que hors de l'année en cours.
    private var monthTitle: String {
        let m = month.formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased()
        return cal.isDate(month, equalTo: .now, toGranularity: .year) ? m : "\(m) \(cal.component(.year, from: month))"
    }

    private func isWeekendColumn(_ i: Int) -> Bool {
        let weekday = (cal.firstWeekday - 1 + i) % 7 + 1
        return weekday == 1 || weekday == 7
    }

    private func dayCell(_ day: Date, rowHeight: CGFloat) -> some View {
        let today = cal.isDateInToday(day)
        let selected = cal.isDate(day, inSameDayAs: selectedDate)
        let weekend = cal.isDateInWeekend(day)
        let busy = busyDays.contains(cal.startOfDay(for: day))
        let dot: CGFloat = 2.5
        let size = min(18, max(11, rowHeight - dot - 1))   // pastille + point tiennent dans la ligne
        return Button { selectedDate = day } label: {
            VStack(spacing: 0) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: min(11, size * 0.68), weight: today || selected ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(today ? .white : Color(white: weekend ? 0.45 : 0.9))
                    .frame(width: size, height: size)
                    .background {
                        if today { Circle().fill(Color.calendarAccent) }
                        else if selected { Circle().fill(.white.opacity(0.16)) }
                    }
                Circle().fill(busy ? Color(white: 0.6) : .clear).frame(width: dot, height: dot)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shift(_ months: Int, _ icon: String) -> some View {
        Button {
            if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
        } label: {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(white: 0.45))
                .frame(width: 14, height: 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    /// Rouge « Calendrier » des maquettes de référence (aujourd'hui, jour, mois).
    static let calendarAccent = Color(red: 1, green: 0.27, blue: 0.23)
}

/// Ouvre Calendrier.app en vue jour sur `date`.
private func openInCalendarApp(_ date: Date) {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    guard let y = c.year, let m = c.month, let d = c.day else { return }
    let script = """
    set d to current date
    set day of d to 1
    set year of d to \(y)
    set month of d to \(m)
    set day of d to \(d)
    tell application "Calendar"
        activate
        switch view to day view
        view calendar at d
    end tell
    """
    Task { _ = try? await AppleScriptHelper.execute(script) }
}

/// Carte d'événement : fond teinté de la couleur du calendrier, barre à gauche, horaires, bouton Rejoindre.
private struct EventCard: View {
    let event: EventModel
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showFullEventTitles) private var showFullTitles

    private var color: Color { Color(event.calendar.color) }
    /// Couleur du calendrier éclaircie pour rester lisible sur fond noir.
    private var textColor: Color { Color(nsColor: event.calendar.color.blended(withFraction: 0.35, of: .white) ?? event.calendar.color) }

    var body: some View {
        Button { if let url = event.calendarAppURL() { openURL(url) } } label: {
            if event.type.isReminder { reminder } else { card }
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        let ended = event.end < .now
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(showFullTitles ? 2 : 1)
                Text(timeText)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(textColor.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !ended, let join = event.meetingURL {
                Button { openURL(join) } label: {
                    Text("Rejoindre")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
                .help(join.host ?? "")
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.16)))
        .contentShape(Rectangle())
        .opacity(ended ? 0.45 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return "Toute la journée" + (event.location.map { $0.isEmpty ? "" : " · \($0)" } ?? "") }
        let t = Date.FormatStyle().hour().minute()
        return "\(event.start.formatted(t)) – \(event.end.formatted(t))"
    }

    private var reminder: some View {
        let done: Bool = { if case .reminder(let c) = event.type { return c } else { return false } }()
        return HStack(spacing: 8) {
            ReminderToggle(
                isOn: Binding(get: { done }, set: { v in
                    Task { await calendarManager.setReminderCompleted(reminderID: event.id, completed: v) }
                }),
                color: color
            )
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !event.isAllDay {
                Text(event.start.formatted(Date.FormatStyle().hour().minute()))
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color(white: 0.6))
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
        .contentShape(Rectangle())
        .opacity(done ? 0.45 : 1)
    }
}

extension EventModel {
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "whereby.com", "facetime.apple.com", "meet.jit.si", "around.co"]

    /// Lien de visio trouvé dans l'URL, le lieu ou les notes de l'événement.
    var meetingURL: URL? {
        let text = [url?.absoluteString, location, notes].compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).lazy
            .compactMap(\.url)
            .first { url in Self.meetingHosts.contains { url.host?.hasSuffix($0) == true } }
    }
}

/// Filtre commun (rappels terminés, journées entières) selon les réglages.
enum EventListView {
    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if case .reminder(let completed) = event.type, completed, Defaults[.hideCompletedReminders] { return false }
            return !(event.isAllDay && Defaults[.hideAllDayEvents])
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
        .frame(width: 640, height: 150)
        .background(.black)
        .environmentObject(BoringViewModel())
}
