import HealthKit
import Foundation

struct WorkoutDetail {
    var name: String
    var sportIdentifier: String?
    var startDate: Date
    var endDate: Date
    var time: String
    var location: String?
    var durationSeconds: TimeInterval
    var durationMinutes: Int
    var calories: Int?
    var avgHR: Int?
    var maxHR: Int?
    var minHR: Int?
    var hrSampleCount: Int?
    var zones: [(label: String, range: String, time: String)]?
    var metadata: [(key: String, value: String)]
}

struct HealthSummary {
    // Activity (today)
    var steps: Int?
    var activeCalories: Int?
    var basalEnergy: Int?
    var exerciseMinutes: Int?
    var standHours: Int?
    var flightsClimbed: Int?
    var distanceKm: Double?

    // Heart (latest/today)
    var restingHR: Int?
    var avgHR: Int?
    var minHR: Int?
    var maxHR: Int?
    var hrv: Double?

    // Vitals
    var respiratoryRate: Double?
    var respiratoryMin: Double?
    var respiratoryMax: Double?

    // Body
    var weightKg: Double?
    var bmi: Double?
    var bodyFatPercent: Double?
    var leanBodyMassKg: Double?

    // Mobility
    var walkingSpeedKmh: Double?
    var stepLengthCm: Double?
    var doubleSupportPercent: Double?
    var walkingAsymmetryPercent: Double?
    var stairAscentSpeedKmh: Double?
    var stairDescentSpeedKmh: Double?
    var sixMinWalkM: Double?

    // Hearing
    var envSoundDb: Double?

    // VO2 Max
    var vo2Max: Double?

    // Other
    var timeInDaylightMin: Double?

    // Workouts (last 14 days)
    var workouts: [WorkoutDetail] = []

    var todayStepCount: Int { steps ?? 0 }
    var workoutCount: Int { workouts.count }
}

@MainActor
class HealthManager: ObservableObject {
    private let store = HKHealthStore()
    @Published var progress: Double = 0
    @Published var progressLabel: String = ""

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let quantities: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .appleExerciseTime, .flightsClimbed, .distanceWalkingRunning,
            .bodyMass, .bodyMassIndex, .bodyFatPercentage, .leanBodyMass,
            .vo2Max,
            .walkingSpeed, .walkingStepLength, .walkingDoubleSupportPercentage,
            .walkingAsymmetryPercentage, .stairAscentSpeed, .stairDescentSpeed,
            .sixMinuteWalkTestDistance,
            .respiratoryRate, .environmentalAudioExposure,
            .timeInDaylight
        ]
        for id in quantities {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let stand = HKObjectType.categoryType(forIdentifier: .appleStandHour) { types.insert(stand) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }()

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSummary(from start: Date, to end: Date) async throws -> HealthSummary {
        var s = HealthSummary()
        // For slow-changing metrics (body, mobility, VO2), look back up to 90 days
        // so they always show even when the selected range is just "Today"
        let extStart = min(start, Calendar.current.date(byAdding: .day, value: -90, to: end)!)

        progress = 0; progressLabel = "Reading activity…"
        async let steps     = fetchRangeSum(.stepCount, unit: .count(), from: start, to: end)
        async let activeCal = fetchRangeSum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        async let basalCal  = fetchRangeSum(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        async let exercise  = fetchRangeSum(.appleExerciseTime, unit: .minute(), from: start, to: end)
        async let flights   = fetchRangeSum(.flightsClimbed, unit: .count(), from: start, to: end)
        async let distance  = fetchRangeSum(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), from: start, to: end)
        async let stand     = fetchStandHours(from: start, to: end)
        s.steps          = await (try? steps).map { Int($0) }
        s.activeCalories = await (try? activeCal).map { Int($0) }
        s.basalEnergy    = await (try? basalCal).map { Int($0) }
        s.exerciseMinutes = await (try? exercise).map { Int($0) }
        s.flightsClimbed = await (try? flights).map { Int($0) }
        s.distanceKm     = await (try? distance) ?? nil
        s.standHours     = await (try? stand) ?? nil

        progress = 0.25; progressLabel = "Reading heart data…"
        async let restHR = fetchRangeDiscrete(.restingHeartRate, unit: hrUnit(), option: .discreteAverage, from: start, to: end)
        async let avgHR  = fetchRangeDiscrete(.heartRate, unit: hrUnit(), option: .discreteAverage, from: start, to: end)
        async let minHR  = fetchRangeDiscrete(.heartRate, unit: hrUnit(), option: .discreteMin, from: start, to: end)
        async let maxHR  = fetchRangeDiscrete(.heartRate, unit: hrUnit(), option: .discreteMax, from: start, to: end)
        async let hrv    = fetchLatestInRange(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: extStart, to: end)
        async let respAvg = fetchRangeDiscrete(.respiratoryRate, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, from: start, to: end)
        async let respMin = fetchRangeDiscrete(.respiratoryRate, unit: .count().unitDivided(by: .minute()), option: .discreteMin, from: start, to: end)
        async let respMax = fetchRangeDiscrete(.respiratoryRate, unit: .count().unitDivided(by: .minute()), option: .discreteMax, from: start, to: end)
        s.restingHR      = await (try? restHR).flatMap { $0.map { Int($0) } }
        s.avgHR          = await (try? avgHR).flatMap { $0.map { Int($0) } }
        s.minHR          = await (try? minHR).flatMap { $0.map { Int($0) } }
        s.maxHR          = await (try? maxHR).flatMap { $0.map { Int($0) } }
        s.hrv            = await (try? hrv) ?? nil
        s.respiratoryRate = await (try? respAvg) ?? nil
        s.respiratoryMin  = await (try? respMin) ?? nil
        s.respiratoryMax  = await (try? respMax) ?? nil

        progress = 0.5; progressLabel = "Reading body metrics…"
        async let weight = fetchLatestInRange(.bodyMass, unit: .gramUnit(with: .kilo), from: extStart, to: end)
        async let bmi    = fetchLatestInRange(.bodyMassIndex, unit: .count(), from: extStart, to: end)
        async let bf     = fetchLatestInRange(.bodyFatPercentage, unit: .percent(), from: extStart, to: end)
        async let lean   = fetchLatestInRange(.leanBodyMass, unit: .gramUnit(with: .kilo), from: extStart, to: end)
        async let vo2    = fetchLatestInRange(.vo2Max, unit: vo2Unit(), from: extStart, to: end)
        async let wSpeed = fetchLatestInRange(.walkingSpeed, unit: .meterUnit(with: .kilo).unitDivided(by: .hour()), from: extStart, to: end)
        async let wStep  = fetchLatestInRange(.walkingStepLength, unit: .meterUnit(with: .centi), from: extStart, to: end)
        async let dSupp  = fetchLatestInRange(.walkingDoubleSupportPercentage, unit: .percent(), from: extStart, to: end)
        async let wAsym  = fetchLatestInRange(.walkingAsymmetryPercentage, unit: .percent(), from: extStart, to: end)
        async let sAsc   = fetchLatestInRange(.stairAscentSpeed, unit: .meterUnit(with: .kilo).unitDivided(by: .hour()), from: extStart, to: end)
        async let sDesc  = fetchLatestInRange(.stairDescentSpeed, unit: .meterUnit(with: .kilo).unitDivided(by: .hour()), from: extStart, to: end)
        async let sixMin = fetchLatestInRange(.sixMinuteWalkTestDistance, unit: .meter(), from: extStart, to: end)
        async let envDb     = fetchRangeDiscrete(.environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel(), option: .discreteAverage, from: start, to: end)
        async let daylight  = fetchRangeSum(.timeInDaylight, unit: .minute(), from: start, to: end)
        s.weightKg           = await (try? weight) ?? nil
        s.bmi                = await (try? bmi) ?? nil
        s.bodyFatPercent     = await (try? bf).flatMap { $0.map { $0 * 100 } }
        s.leanBodyMassKg     = await (try? lean) ?? nil
        s.vo2Max             = await (try? vo2) ?? nil
        s.walkingSpeedKmh    = await (try? wSpeed) ?? nil
        s.stepLengthCm       = await (try? wStep) ?? nil
        s.doubleSupportPercent    = await (try? dSupp).flatMap { $0.map { $0 * 100 } }
        s.walkingAsymmetryPercent = await (try? wAsym).flatMap { $0.map { $0 * 100 } }
        s.stairAscentSpeedKmh    = await (try? sAsc) ?? nil
        s.stairDescentSpeedKmh   = await (try? sDesc) ?? nil
        s.sixMinWalkM            = await (try? sixMin) ?? nil
        s.envSoundDb             = await (try? envDb) ?? nil
        s.timeInDaylightMin      = await (try? daylight).map { $0 > 0 ? $0 : nil } ?? nil

        progress = 0.75; progressLabel = "Reading workouts…"
        s.workouts = (try? await fetchWorkouts(from: start, to: end)) ?? []

        progress = 1.0; progressLabel = "Done"
        s.bodyFatPercent    = await (try? bf).flatMap { $0.map { $0 * 100 } }
        return s
    }

    // MARK: - Helpers

    private func hrUnit() -> HKUnit { .count().unitDivided(by: .minute()) }

    private func vo2Unit() -> HKUnit {
        HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    }

    private func fetchRangeSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchRangeDiscrete(_ id: HKQuantityTypeIdentifier, unit: HKUnit, option: HKStatisticsOptions, from start: Date, to end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: option) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                let val: Double?
                switch option {
                case .discreteAverage: val = stats?.averageQuantity()?.doubleValue(for: unit)
                case .discreteMin:     val = stats?.minimumQuantity()?.doubleValue(for: unit)
                case .discreteMax:     val = stats?.maximumQuantity()?.doubleValue(for: unit)
                default:               val = stats?.averageQuantity()?.doubleValue(for: unit)
                }
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    private func fetchLatestInRange(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func fetchStandHours(from start: Date, to end: Date) async throws -> Int {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let count = (samples as? [HKCategorySample])?.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count ?? 0
                cont.resume(returning: count)
            }
            store.execute(q)
        }
    }

    private func fetchWorkouts(from start: Date, to end: Date) async throws -> [WorkoutDetail] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let raw: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 20, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(q)
        }

        var details: [WorkoutDetail] = []
        for w in raw {
            let detail = await buildWorkoutDetail(w)
            details.append(detail)
        }
        return details
    }

    private func buildWorkoutDetail(_ w: HKWorkout) async -> WorkoutDetail {
        let hrType = HKQuantityType(.heartRate)
        let avgHR = w.statistics(for: hrType)?.averageQuantity().map { Int($0.doubleValue(for: hrUnit())) }
        let maxHR = w.statistics(for: hrType)?.maximumQuantity().map { Int($0.doubleValue(for: hrUnit())) }
        let minHR = w.statistics(for: hrType)?.minimumQuantity().map { Int($0.doubleValue(for: hrUnit())) }
        let cal   = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie())) }

        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let iso = ISO8601DateFormatter()

        let isOutdoor = (w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool).map { !$0 }
        let location = isOutdoor == true ? "Outdoor" : (isOutdoor == false ? "Indoor" : nil)

        // Sport identifier from metadata
        let sportId = w.metadata?["HKExternalUUID"] as? String

        // HR zones with BPM ranges — compute from max observed HR (use year-wide max as proxy for true max)
        var zones: [(label: String, range: String, time: String)]? = nil
        let hrSamples = await fetchHRSamples(for: w)
        if let maxHRVal = maxHR, maxHRVal > 0 {
            // Use the higher of observed max or 220-based estimate; fall back to year max
            let yearMax = await (try? fetchYearMaxHR()) ?? maxHRVal
            // Clamp year max: if it's >20% above workout max it's likely a bad sample
            let clampedYearMax = yearMax > Int(Double(maxHRVal) * 1.2) ? maxHRVal : yearMax
            let trueMax = max(clampedYearMax, maxHRVal)
            zones = computeHRZones(samples: hrSamples, maxHR: trueMax)
        }

        // Metadata
        var meta: [(String, String)] = []
        if let mets = w.metadata?[HKMetadataKeyAverageMETs] as? HKQuantity {
            meta.append(("HKAverageMETs", String(format: "%.6g kcal/hr·kg", mets.doubleValue(for: .kilocalorie().unitDivided(by: .hour().unitMultiplied(by: .gramUnit(with: .kilo)))))))
        }
        if let indoor = w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            meta.append(("HKIndoorWorkout", indoor ? "true" : "false"))
        }
        if let tz = w.metadata?[HKMetadataKeyTimeZone] as? String {
            meta.append(("HKTimeZone", tz))
        }
        if let humidity = w.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity {
            meta.append(("HKWeatherHumidity", String(format: "%.0f %%", humidity.doubleValue(for: .percent()) * 100)))
        }
        if let temp = w.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            meta.append(("HKWeatherTemperature", String(format: "%.6g degF", temp.doubleValue(for: .degreeFahrenheit()))))
        }

        // Duration string mm:ss
        let dSec = Int(w.duration)
        let durStr = String(format: "%d:%02d", dSec / 60, dSec % 60)

        return WorkoutDetail(
            name: w.workoutActivityType.displayName,
            sportIdentifier: w.workoutActivityType.hkIdentifier,
            startDate: w.startDate,
            endDate: w.endDate,
            time: tf.string(from: w.startDate),
            location: location,
            durationSeconds: w.duration,
            durationMinutes: dSec / 60,
            calories: cal,
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: minHR,
            hrSampleCount: hrSamples.count,
            zones: zones,
            metadata: meta
        )
    }

    private func fetchHRSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return (try? await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: s as? [HKQuantitySample] ?? [])
            }
            store.execute(q)
        }) ?? []
    }

    private func fetchYearMaxHR() async throws -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let start = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        // Try statistics query first
        let statsMax: Int = try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMax) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: Int(stats?.maximumQuantity()?.doubleValue(for: self.hrUnit()) ?? 0))
            }
            store.execute(q)
        }

        // Also scan recent workouts' max HR as a fallback
        let workoutMax: Int = try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let max = (samples as? [HKWorkout] ?? []).compactMap {
                    $0.statistics(for: type)?.maximumQuantity()?.doubleValue(for: self.hrUnit())
                }.max().map { Int($0) } ?? 0
                cont.resume(returning: max)
            }
            self.store.execute(q)
        }

        return max(statsMax, workoutMax)
    }

    private func computeHRZones(samples: [HKQuantitySample], maxHR: Int) -> [(label: String, range: String, time: String)]? {
        guard samples.count > 1 else { return nil }
        let mhr = Double(maxHR)
        // Classification: anything below 50% counts as Recovery
        let classBoundaries = [0.0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.01]
        // Display: Zone 1 lower bound shown as 50% of max HR
        let displayLo       = [0.5,  0.6,  0.7,  0.8,  0.9]
        let displayHi       = [0.6,  0.7,  0.8,  0.9,  1.0]
        let labels = ["Recovery", "Aerobic", "Tempo", "Threshold", "Max"]
        var zoneSecs = [Double](repeating: 0, count: 5)

        for i in 0..<samples.count - 1 {
            let bpm = samples[i].quantity.doubleValue(for: hrUnit())
            let dt = samples[i+1].startDate.timeIntervalSince(samples[i].startDate)
            guard dt > 0 && dt < 300 else { continue }
            let pct = bpm / mhr
            for z in 0..<5 {
                if pct >= classBoundaries[z] && pct < classBoundaries[z+1] { zoneSecs[z] += dt; break }
            }
        }

        return (0..<5).map { z -> (String, String, String) in
            let lo = Int(mhr * displayLo[z])
            let hi = min(Int(mhr * displayHi[z]), maxHR)
            let range = "\(lo)-\(hi) bpm"
            let secs = Int(zoneSecs[z])
            let timeStr = zoneSecs[z] > 0 ? String(format: "%d:%02d", secs / 60, secs % 60) : "—"
            return (labels[z], range, timeStr)
        }
    }

}

extension HKWorkoutActivityType {
    var hkIdentifier: String {
        switch self {
        case .running:                      return "running"
        case .cycling:                      return "cycling"
        case .walking:                      return "walking"
        case .swimming:                     return "swimming"
        case .yoga:                         return "yoga"
        case .functionalStrengthTraining:   return "functionalStrengthTraining"
        case .traditionalStrengthTraining:  return "traditionalStrengthTraining"
        case .highIntensityIntervalTraining:return "highIntensityIntervalTraining"
        case .hiking:                       return "hiking"
        case .rowing:                       return "rowing"
        case .pilates:                      return "pilates"
        case .elliptical:                   return "elliptical"
        case .stairClimbing:                return "stairClimbing"
        default:                            return "other"
        }
    }

    var displayName: String {
        switch self {
        case .running:                      return "Running"
        case .cycling:                      return "Cycling"
        case .walking:                      return "Walking"
        case .swimming:                     return "Swimming"
        case .yoga:                         return "Yoga"
        case .functionalStrengthTraining:   return "Strength Training"
        case .traditionalStrengthTraining:  return "Strength Training"
        case .highIntensityIntervalTraining:return "HIIT"
        case .hiking:                       return "Hiking"
        case .rowing:                       return "Rowing"
        case .pilates:                      return "Pilates"
        case .dance:                        return "Dance"
        case .elliptical:                   return "Elliptical"
        case .stairClimbing:                return "Stair Climbing"
        case .crossTraining:                return "Cross Training"
        case .flexibility:                  return "Flexibility"
        case .cooldown:                     return "Cooldown"
        default:                            return "Workout"
        }
    }
}

