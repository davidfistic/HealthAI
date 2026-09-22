import SwiftUI
import HealthKit

enum DateRange: Equatable {
    case today, yesterday, allTime, custom(Date, Date)

    var label: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .allTime:   return "All Time"
        case .custom:    return "Custom"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    func startEnd() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .yesterday:
            let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
            return (cal.startOfDay(for: yesterday), cal.startOfDay(for: now))
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
        case .custom(let s, let e):
            return (cal.startOfDay(for: s), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e))!)
        }
    }
}

struct ContentView: View {
    @StateObject private var health = HealthManager()
    @AppStorage("hasGrantedHealth") private var hasGrantedHealth = false

    @State private var selectedRange: DateRange = .today
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd = Date()
    @State private var showingCustomPicker = false

    @State private var isLoading = false
    @State private var errorMessage: String?

    private var authorized: Bool { hasGrantedHealth }
    private let ranges: [DateRange] = [.today, .yesterday, .allTime, .custom(Date(), Date())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !authorized {
                        onboardingView
                    } else {
                        mainView
                    }
                }
                .padding()
            }
            .navigationTitle("HealthAI")
            .onAppear {
                Task { try? await health.requestAuthorization() }
            }
            .toolbar {
                if authorized {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let url = URL(string: "x-apple-health://") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCustomPicker) {
            CustomDatePickerSheet(start: $customStart, end: $customEnd) {
                selectedRange = .custom(customStart, customEnd)
            }
        }
    }

    private var onboardingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)
                .padding(.top, 40)

            Text("Connect Apple Health")
                .font(.title2.bold())

            Text("HealthAI reads your Apple Health data and formats it so you can share it with Claude via email, Notes, or anywhere else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                Task { await requestAuth() }
            } label: {
                Label("Allow Health Access", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var mainView: some View {
        VStack(spacing: 20) {
            dateRangePicker

            Button {
                Task { await exportData() }
            } label: {
                Label("Export Health Data", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isLoading ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading)

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView(value: health.progress)
                        .tint(.blue)
                    Text(health.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if let error = errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text(error).font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var dateRangePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date Range")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([DateRange.today, .yesterday, .allTime, .custom(customStart, customEnd)], id: \.label) { range in
                    let isSelected: Bool = {
                        switch (selectedRange, range) {
                        case (.today, .today), (.yesterday, .yesterday), (.allTime, .allTime): return true
                        case (.custom, .custom): return true
                        default: return false
                        }
                    }()

                    Button {
                        if range.isCustom {
                            showingCustomPicker = true
                        } else {
                            selectedRange = range
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.purple)
                            }
                            Text(range.label)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .purple : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(isSelected ? Color.purple.opacity(0.12) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            if case .custom(let s, let e) = selectedRange {
                let df = DateFormatter()
                let _ = { df.dateStyle = .medium }()
                Text("\(df.string(from: s)) – \(df.string(from: e))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func requestAuth() async {
        do {
            try await health.requestAuthorization()
            hasGrantedHealth = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportData() async {
        isLoading = true
        errorMessage = nil
        do {
            let (start, end) = selectedRange.startEnd()
            let summary = try await health.fetchSummary(from: start, to: end)
            let text = formatOutput(summary, range: selectedRange)
            await presentShareSheet(with: text)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func presentShareSheet(with text: String) async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        top.present(vc, animated: true)
    }

    private func formatOutput(_ s: HealthSummary, range: DateRange) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        let (start, end) = range.startEnd()
        let dateLabel: String = {
            switch range {
            case .today:     return df.string(from: Date())
            case .yesterday: return df.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            case .allTime:   return "All Time"
            case .custom:    return "\(df.string(from: start)) – \(df.string(from: end))"
            }
        }()

        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("schema: healthai.health_data")
        lines.append("schema_version: 1")
        lines.append("date: \(dateLabel)")
        lines.append("type: health-data")
        if let v = s.steps              { lines.append("steps: \(v)") }
        if let v = s.activeCalories     { lines.append("active_calories: \(v)") }
        if let v = s.basalEnergy        { lines.append("basal_calories: \(v)") }
        if let v = s.exerciseMinutes    { lines.append("exercise_minutes: \(v)") }
        if let v = s.standHours         { lines.append("stand_hours: \(v)") }
        if let v = s.flightsClimbed     { lines.append("flights_climbed: \(v)") }
        if let v = s.distanceKm         { lines.append(String(format: "walking_running_km: %.2f", v)); lines.append(String(format: "walking_running_mi: %.2f", v * 0.621371)) }
        if let v = s.vo2Max             { lines.append(String(format: "vo2_max: %.1f", v)) }
        if let v = s.timeInDaylightMin  { lines.append(String(format: "time_in_daylight_min: %.0f", v)) }
        if let v = s.restingHR          { lines.append("resting_heart_rate: \(v)") }
        if let v = s.avgHR              { lines.append("average_heart_rate: \(v)") }
        if let v = s.minHR              { lines.append("heart_rate_min: \(v)") }
        if let v = s.maxHR              { lines.append("heart_rate_max: \(v)") }
        if let v = s.hrv                { lines.append(String(format: "hrv_ms: %.1f", v)) }
        if let v = s.respiratoryRate    { lines.append(String(format: "respiratory_rate: %.1f", v)) }
        if let v = s.respiratoryRate    { lines.append(String(format: "respiratory_rate_avg: %.1f", v)) }
        if let v = s.respiratoryMin     { lines.append(String(format: "respiratory_rate_min: %.1f", v)) }
        if let v = s.respiratoryMax     { lines.append(String(format: "respiratory_rate_max: %.1f", v)) }
        if let v = s.weightKg           { lines.append(String(format: "weight_kg: %.1f", v)) }
        if let v = s.bmi                { lines.append(String(format: "bmi: %.1f", v)) }
        if let v = s.bodyFatPercent     { lines.append(String(format: "body_fat_percent: %.1f", v)) }
        if let v = s.leanBodyMassKg     { lines.append(String(format: "lean_body_mass_kg: %.1f", v)) }
        if let v = s.walkingSpeedKmh    { lines.append(String(format: "walking_speed: %.2f", v / 3.6)) }
        if let v = s.stepLengthCm       { lines.append(String(format: "step_length_cm: %.1f", v)) }
        if let v = s.doubleSupportPercent    { lines.append(String(format: "double_support_percent: %.1f", v)) }
        if let v = s.walkingAsymmetryPercent { lines.append(String(format: "walking_asymmetry_percent: %.1f", v)) }
        if let v = s.stairAscentSpeedKmh     { lines.append(String(format: "stair_ascent_speed: %.2f", v / 3.6)) }
        if let v = s.stairDescentSpeedKmh    { lines.append(String(format: "stair_descent_speed: %.2f", v / 3.6)) }
        if let v = s.sixMinWalkM        { lines.append(String(format: "six_min_walk_m: %.0f", v)) }
        if let v = s.envSoundDb         { lines.append(String(format: "environmental_sound_db: %.1f", v)) }
        if !s.workouts.isEmpty {
            let wc = s.workouts.count
            let totalCal = s.workouts.compactMap { $0.calories }.reduce(0, +)
            let totalMin = s.workouts.map { $0.durationMinutes }.reduce(0, +)
            let avgHRs = s.workouts.compactMap { $0.avgHR }
            let avgHRAvg = avgHRs.isEmpty ? nil : avgHRs.reduce(0, +) / avgHRs.count
            let maxHRs = s.workouts.compactMap { $0.maxHR }.max()
            let minHRs = s.workouts.compactMap { $0.minHR }.min()
            lines.append("workout_count: \(wc)")
            if totalCal > 0 { lines.append("workout_calories: \(totalCal)") }
            lines.append("workout_minutes: \(totalMin)")
            if let v = avgHRAvg { lines.append("workout_avg_heart_rate: \(v)") }
            if let v = maxHRs   { lines.append("workout_max_heart_rate: \(v)") }
            if let v = minHRs   { lines.append("workout_min_heart_rate: \(v)") }
            let types = s.workouts.compactMap { $0.sportIdentifier }.joined(separator: ", ")
            if !types.isEmpty { lines.append("workouts: [\(types)]") }
        }
        lines.append("---")
        lines.append("")

        lines.append("# Health Data — \(dateLabel)")
        lines.append("")

        var summaryParts: [String] = []
        if let steps = s.steps { summaryParts.append("\(steps) steps") }
        let wc2 = s.workouts.count
        if wc2 > 0 { summaryParts.append("\(wc2) workout\(wc2 == 1 ? "" : "s")") }
        if !summaryParts.isEmpty { lines.append(summaryParts.joined(separator: " · ")); lines.append("") }

        lines.append("## Activity"); lines.append("")
        if let v = s.steps              { lines.append("- **Steps:** \(v)") }
        if let v = s.activeCalories     { lines.append("- **Active Calories:** \(v) kcal") }
        if let v = s.basalEnergy        { lines.append("- **Basal Energy:** \(v) kcal") }
        if let v = s.exerciseMinutes    { lines.append("- **Exercise:** \(v) min") }
        if let v = s.standHours         { lines.append("- **Stand Hours:** \(v)") }
        if let v = s.flightsClimbed     { lines.append("- **Flights Climbed:** \(v)") }
        if let v = s.distanceKm         { lines.append(String(format: "- **Walking/Running Distance:** %.2f km", v)) }
        if let v = s.vo2Max             { lines.append(String(format: "- **Cardio Fitness (VO2 Max):** %.1f mL/kg/min", v)) }
        lines.append("")

        var heartLines: [String] = []
        if let v = s.restingHR { heartLines.append("- **Resting HR:** \(v) bpm") }
        if let v = s.avgHR     { heartLines.append("- **Average HR:** \(v) bpm") }
        if let v = s.minHR     { heartLines.append("- **Min HR:** \(v) bpm") }
        if let v = s.maxHR     { heartLines.append("- **Max HR:** \(v) bpm") }
        if let v = s.hrv       { heartLines.append(String(format: "- **HRV:** %.1f ms", v)) }
        if !heartLines.isEmpty { lines.append("## Heart"); lines.append(""); lines.append(contentsOf: heartLines); lines.append("") }

        if let v = s.respiratoryRate {
            lines.append("## Vitals"); lines.append("")
            var resp = String(format: "- **Respiratory Rate:** %.1f breaths/min", v)
            if let mn = s.respiratoryMin, let mx = s.respiratoryMax {
                resp += String(format: " (range: %.1f–%.1f)", mn, mx)
            }
            lines.append(resp); lines.append("")
        }

        var bodyLines: [String] = []
        if let v = s.weightKg       { bodyLines.append(String(format: "- **Weight:** %.1f kg", v)) }
        if let v = s.bmi            { bodyLines.append(String(format: "- **BMI:** %.1f", v)) }
        if let v = s.bodyFatPercent { bodyLines.append(String(format: "- **Body Fat:** %.1f%%", v)) }
        if let v = s.leanBodyMassKg { bodyLines.append(String(format: "- **Lean Body Mass:** %.1f kg", v)) }
        if !bodyLines.isEmpty { lines.append("## Body"); lines.append(""); lines.append(contentsOf: bodyLines); lines.append("") }

        var mobLines: [String] = []
        if let v = s.walkingSpeedKmh         { mobLines.append(String(format: "- **Walking Speed:** %.1f km/h", v)) }
        if let v = s.stepLengthCm            { mobLines.append(String(format: "- **Step Length:** %.1f cm", v)) }
        if let v = s.doubleSupportPercent    { mobLines.append(String(format: "- **Double Support:** %.1f%%", v)) }
        if let v = s.walkingAsymmetryPercent { mobLines.append(String(format: "- **Walking Asymmetry:** %.1f%%", v)) }
        if let v = s.stairAscentSpeedKmh     { mobLines.append(String(format: "- **Stair Ascent Speed:** %.1f km/h", v)) }
        if let v = s.stairDescentSpeedKmh    { mobLines.append(String(format: "- **Stair Descent Speed:** %.1f km/h", v)) }
        if let v = s.sixMinWalkM             { mobLines.append(String(format: "- **6-Min Walk Distance:** %.0f m", v)) }
        if !mobLines.isEmpty { lines.append("## Mobility"); lines.append(""); lines.append(contentsOf: mobLines); lines.append("") }

        if let v = s.envSoundDb {
            lines.append("## Hearing"); lines.append("")
            lines.append(String(format: "- **Environmental Sound Level:** %.1f dB", v))
            lines.append("")
        }

        if !s.workouts.isEmpty {
            lines.append("## Workouts"); lines.append("")
            for (i, w) in s.workouts.enumerated() {
                let dSec = Int(w.durationSeconds)
                let durStr = String(format: "%d:%02d", dSec / 60, dSec % 60)

                lines.append("### \(i + 1). \(w.name)"); lines.append("")
                lines.append("- **Time:** \(w.time)")
                if let loc = w.location { lines.append("- **Location:** \(loc)") }
                lines.append("- **Duration:** \(w.durationMinutes)m")
                if let v = w.calories { lines.append("- **Calories:** \(v) kcal") }
                if let v = w.avgHR    { lines.append("- **Avg Heart Rate:** \(v) bpm") }
                if let v = w.maxHR    { lines.append("- **Max Heart Rate:** \(v) bpm") }
                if let v = w.minHR    { lines.append("- **Min Heart Rate:** \(v) bpm") }

                // Zone summary line
                if let zones = w.zones, !zones.isEmpty {
                    let zoneSummary = zones.filter { $0.time != "—" }.map { "\($0.label) \($0.time)" }.joined(separator: " · ")
                    if !zoneSummary.isEmpty { lines.append("- **Heart Rate Zones:** \(zoneSummary)") }
                }
                lines.append("")

                // Details table
                lines.append("#### Details"); lines.append("")
                lines.append("| Field | Value |")
                lines.append("|---|---|")
                lines.append("| Activity Type | \(w.name) |")
                if let sport = w.sportIdentifier { lines.append("| Sport | \(sport) |") }
                lines.append("| Start | \(iso.string(from: w.startDate)) |")
                lines.append("| End | \(iso.string(from: w.endDate)) |")
                lines.append("| Duration | \(durStr) |")
                if let loc = w.location { lines.append("| Location | \(loc) |") }
                if let v = w.calories { lines.append("| Calories | \(v) kcal |") }
                if let v = w.avgHR    { lines.append("| Avg Heart Rate | \(v) bpm |") }
                if let v = w.maxHR    { lines.append("| Max Heart Rate | \(v) bpm |") }
                if let v = w.minHR    { lines.append("| Min Heart Rate | \(v) bpm |") }

                // Zones table
                if let zones = w.zones, !zones.isEmpty {
                    lines.append("")
                    lines.append("- **Heart Rate Zones:**"); lines.append("")
                    lines.append("| Zone | Label | Range | Time |")
                    lines.append("|---|---|---|---|")
                    for (zi, z) in zones.enumerated() {
                        lines.append("| Zone \(zi+1) | \(z.label) | \(z.range) | \(z.time) |")
                    }
                }

                // Samples
                if let count = w.hrSampleCount, count > 0 {
                    lines.append("")
                    lines.append("#### Samples"); lines.append("")
                    lines.append("| Metric | Samples |")
                    lines.append("|---|---:|")
                    lines.append("| Heart Rate | \(count) |")
                }

                // Metadata
                if !w.metadata.isEmpty {
                    lines.append("")
                    lines.append("#### Metadata"); lines.append("")
                    lines.append("| Key | Value |")
                    lines.append("|---|---|")
                    for m in w.metadata { lines.append("| \(m.key) | \(m.value) |") }
                }

                lines.append("")
            }
        }

        // Other
        var otherLines: [String] = []
        if let v = s.timeInDaylightMin { otherLines.append(String(format: "- **Time in Daylight:** %.0f min", v)) }
        if !otherLines.isEmpty { lines.append("## Other"); lines.append(""); lines.append(contentsOf: otherLines) }

        return lines.joined(separator: "\n")
    }
}

struct CustomDatePickerSheet: View {
    @Binding var start: Date
    @Binding var end: Date
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section("To") {
                    DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(); dismiss() }
                        .bold()
                }
            }
        }
    }
}
