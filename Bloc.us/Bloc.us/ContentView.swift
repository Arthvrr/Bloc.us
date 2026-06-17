import SwiftUI
import Charts
import Foundation
import Combine
import UserNotifications

// MARK: - FORMATTER PERSONNALISÉ
extension NumberFormatter {
    static var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        return formatter
    }
}

// MARK: - MODELS
struct TaskItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var total: Double
    var done: Double
}

struct GradingItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var total: Double
    var score: Double
}

struct CourseEvent: Identifiable, Codable {
    var id = UUID()
    var type: String
    var course: String
    var description: String
}

struct TodoItem: Identifiable, Codable {
    var id = UUID()
    var text: String
    var dueDate: Date?
    var isDone: Bool = false
}

struct LinkItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
}

struct Course: Codable {
    var colorHex: String
    var tasks: [TaskItem]
    var grading: [GradingItem]
    var todos: [TodoItem]?
    var links: [LinkItem]?
    var passingGrade: Double
    var fullName: String
    var professor: String
    var examStartTime: String
    var examEndTime: String
    var examLocation: String
    var category: String?
}

// Modèles pour le Parcours Académique
struct ParcoursCourse: Identifiable, Codable {
    var id = UUID()
    var code: String
    var name: String
    var credits: Double
    var category: String
    var grade: Double
    var attempts: Int
    var semester: String // "Q1" ou "Q2"
}

struct ExamResult: Identifiable, Codable {
    var id = UUID()
    var sessionName: String // "Janvier", "Juin", "Août"
    var courseCode: String
    var grade: Double
    var attempt: Int
}

struct AcademicYear: Identifiable, Codable {
    var id = UUID()
    var yearString: String
    var level: String
    var school: String
    var courses: [ParcoursCourse]
    var exams: [ExamResult]?
}

// MARK: - LOGIQUE INTELLIGENTE DU PARCOURS
extension AcademicYear {
    // Récupère la meilleure note pour un cours du PAE (base + toutes ses sessions)
    func bestGrade(for courseCode: String) -> Double {
        guard let course = courses.first(where: { $0.code == courseCode }) else { return 0 }
        let examGrades = (exams ?? []).filter { $0.courseCode == courseCode }.map { $0.grade }
        return max(course.grade, examGrades.max() ?? 0)
    }

    // Calcule les crédits gagnés spécifiquement dans une session donnée
    func earnedCredits(forSession session: String) -> Double {
        let sessionExams = (exams ?? []).filter { $0.sessionName == session && $0.grade >= 10.0 }
        var credits: Double = 0
        for exam in sessionExams {
            if let course = courses.first(where: { $0.code == exam.courseCode }) {
                credits += course.credits
            }
        }
        return credits
    }

    // Calcule le total de crédits réussis sur l'année (PAE uniquement)
    func totalEarnedCredits() -> Double {
        var earned: Double = 0
        for course in courses {
            if bestGrade(for: course.code) >= 10.0 {
                earned += course.credits
            }
        }
        return earned
    }

    func totalCredits() -> Double {
        courses.reduce(0) { $0 + $1.credits }
    }

    // Moyenne pondérée en utilisant la MEILLEURE note de chaque cours du PAE
    func weightedGPA() -> Double {
        let tot = totalCredits()
        guard tot > 0 else { return 0 }
        var sum: Double = 0
        for course in courses {
            sum += bestGrade(for: course.code) * course.credits
        }
        return sum / tot
    }
}

// Types de zoom possibles
enum ZoomType: String, Identifiable {
    case tableQ1, tableQ2, examsJan, examsJun, examsAug
    case chartNotes, chartCat, chartJan, chartJun, chartAug
    var id: String { self.rawValue }
}

enum GeneralZoomType: String, Identifiable {
    case equilibre, repartition, points
    var id: String { self.rawValue }
}

enum DashboardZoomType: String, Identifiable {
    case chartEvolution
    var id: String { self.rawValue }
}

// MARK: - VIEW MODEL (Auto-Save & Notifications)
class AppData: ObservableObject {
    @Published var courses: [String: Course] = [:] { didSet { save() } }
    @Published var schedule: [String: [CourseEvent]] = [:] { didSet { save() } }
    @Published var academicYears: [AcademicYear] = [] { didSet { save() } }
    
    @Published var currentStreak: Int = 0
    @Published var lastProgressDate: String = ""
    
    init() {
        load()
        requestNotificationPermission()
    }
    
    func save() {
        if let encodedCourses = try? JSONEncoder().encode(courses) { UserDefaults.standard.set(encodedCourses, forKey: "courses") }
        if let encodedSchedule = try? JSONEncoder().encode(schedule) { UserDefaults.standard.set(encodedSchedule, forKey: "schedule") }
        if let encodedYears = try? JSONEncoder().encode(academicYears) { UserDefaults.standard.set(encodedYears, forKey: "academicYears") }
        UserDefaults.standard.set(currentStreak, forKey: "currentStreak")
        UserDefaults.standard.set(lastProgressDate, forKey: "lastProgressDate")
        updateNotifications()
    }
    
    func load() {
        let rawCourses = UserDefaults.standard.data(forKey: "courses")
        let rawSchedule = UserDefaults.standard.data(forKey: "schedule")
        let rawYears = UserDefaults.standard.data(forKey: "academicYears")
        
        if let data = rawCourses, let decoded = try? JSONDecoder().decode([String: Course].self, from: data) { self.courses = decoded }
        if let data = rawSchedule, let decoded = try? JSONDecoder().decode([String: [CourseEvent]].self, from: data) { self.schedule = decoded }
        if let data = rawYears, let decoded = try? JSONDecoder().decode([AcademicYear].self, from: data) { self.academicYears = decoded }
        
        self.currentStreak = UserDefaults.standard.integer(forKey: "currentStreak")
        self.lastProgressDate = UserDefaults.standard.string(forKey: "lastProgressDate") ?? ""
    }
    
    // --- GESTION PARCOURS ACADÉMIQUE ---
    func allParcoursCourses() -> [ParcoursCourse] {
        var uniqueCourses: [String: ParcoursCourse] = [:]
        for year in academicYears {
            for course in year.courses {
                uniqueCourses[course.code] = course
            }
        }
        return Array(uniqueCourses.values).sorted(by: { $0.code < $1.code })
    }
    
    func getParcoursCourse(code: String) -> ParcoursCourse? {
        for year in academicYears.reversed() {
            if let c = year.courses.first(where: { $0.code == code }) { return c }
        }
        return nil
    }
    
    func addParcoursCourse(yearId: UUID, course: ParcoursCourse) {
        objectWillChange.send()
        if let index = academicYears.firstIndex(where: { $0.id == yearId }) {
            academicYears[index].courses.append(course)
            save()
        }
    }
    func updateParcoursCourse(yearId: UUID, course: ParcoursCourse) {
        objectWillChange.send()
        if let yIndex = academicYears.firstIndex(where: { $0.id == yearId }),
           let cIndex = academicYears[yIndex].courses.firstIndex(where: { $0.id == course.id }) {
            academicYears[yIndex].courses[cIndex] = course
            save()
        }
    }
    func removeParcoursCourse(yearId: UUID, courseId: UUID) {
        objectWillChange.send()
        if let index = academicYears.firstIndex(where: { $0.id == yearId }) {
            academicYears[index].courses.removeAll(where: { $0.id == courseId })
            save()
        }
    }
    func addExamResult(yearId: UUID, exam: ExamResult) {
        objectWillChange.send()
        if let index = academicYears.firstIndex(where: { $0.id == yearId }) {
            if academicYears[index].exams == nil { academicYears[index].exams = [] }
            academicYears[index].exams?.append(exam)
            save()
        }
    }
    func removeExamResult(yearId: UUID, examId: UUID) {
        objectWillChange.send()
        if let index = academicYears.firstIndex(where: { $0.id == yearId }) {
            academicYears[index].exams?.removeAll(where: { $0.id == examId })
            save()
        }
    }
    
    // --- GAMIFICATION ---
    func registerActivity() {
        let today = DateFormatter.yyyyMMdd.string(from: Date())
        if lastProgressDate == today { return }
        let yesterday = DateFormatter.yyyyMMdd.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        if lastProgressDate == yesterday { currentStreak += 1 } else { currentStreak = 1 }
        lastProgressDate = today
        save()
    }
    func getDisplayStreak() -> Int {
        let today = DateFormatter.yyyyMMdd.string(from: Date())
        let yesterday = DateFormatter.yyyyMMdd.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        if lastProgressDate == today || lastProgressDate == yesterday { return currentStreak }
        return 0
    }
    
    // --- NOTIFICATIONS ---
    func requestNotificationPermission() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
    func updateNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for (dateStr, events) in schedule {
            if let date = DateFormatter.yyyyMMdd.date(from: dateStr) {
                if events.contains(where: { $0.type == "Étude" }) {
                    scheduleNotification(title: "🎯 Focus du jour", body: "Tu as des sessions d'étude prévues aujourd'hui ! Bon blocus.", date: date, hour: 9, minute: 0, id: "study-\(dateStr)")
                }
                let exams = events.filter { $0.type == "Examen" }
                for exam in exams {
                    if let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: date) {
                        scheduleNotification(title: "🎒 Prêt pour l'examen ?", body: "Demain tu as examen de \(exam.course). Prépare tes affaires !", date: dayBefore, hour: 20, minute: 0, id: "exam-\(exam.id.uuidString)")
                    }
                }
            }
        }
        for (cName, course) in courses {
            if let todos = course.todos {
                for todo in todos {
                    if let dueDate = todo.dueDate, !todo.isDone {
                        if let notifDate = Calendar.current.date(byAdding: .hour, value: -1, to: dueDate), notifDate > Date() {
                            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notifDate)
                            scheduleNotification(title: "⏳ Tâche à terminer bientôt", body: "\(todo.text) (\(cName))", components: comps, id: "todo-\(todo.id.uuidString)")
                        }
                    }
                }
            }
        }
    }
    private func scheduleNotification(title: String, body: String, date: Date, hour: Int, minute: Int, id: String) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour; components.minute = minute
        if let targetDate = Calendar.current.date(from: components), targetDate > Date() { scheduleNotification(title: title, body: body, components: components, id: id) }
    }
    private func scheduleNotification(title: String, body: String, components: DateComponents, id: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    // --- GESTION COURS BLOCUS ---
    func renameCourse(oldName: String, newName: String) {
        guard !newName.isEmpty, oldName != newName, courses[newName] == nil, let course = courses[oldName] else { return }
        courses[newName] = course; courses.removeValue(forKey: oldName)
        for (date, events) in schedule {
            var updatedEvents = events
            for i in 0..<updatedEvents.count { if updatedEvents[i].course == oldName { updatedEvents[i].course = newName } }
            schedule[date] = updatedEvents
        }
        save()
    }
    func addScheduleEvent(date: Date, type: String, course: String, description: String) {
        let dStr = DateFormatter.yyyyMMdd.string(from: date); var currentEvents = schedule[dStr] ?? []
        currentEvents.append(CourseEvent(type: type, course: course, description: description))
        schedule[dStr] = currentEvents; save()
    }
    func removeScheduleEvent(dateStr: String, eventId: UUID) {
        if var currentEvents = schedule[dateStr] {
            currentEvents.removeAll(where: { $0.id == eventId })
            if currentEvents.isEmpty { schedule.removeValue(forKey: dateStr) } else { schedule[dateStr] = currentEvents }; save()
        }
    }
    func computeProgress(for course: String) -> Double {
        guard let c = courses[course] else { return 0 }
        let totalPossible = c.tasks.reduce(0) { $0 + $1.total }
        return totalPossible > 0 ? c.tasks.reduce(0) { $0 + $1.done } / totalPossible : 0
    }
    func computeStudyDays(for course: String) -> (total: Int, remaining: Int) {
        let todayStr = DateFormatter.yyyyMMdd.string(from: Date()); var total = 0, remaining = 0
        for (dateStr, events) in schedule {
            for ev in events where ev.course == course && ev.type == "Étude" { total += 1; if dateStr >= todayStr { remaining += 1 } }
        }
        return (total, remaining)
    }
    func currentStudyDayInfo(for course: String) -> (current: Int, total: Int)? {
        var studyDates: [String] = []
        for (dateStr, events) in schedule { if events.contains(where: { $0.course == course && $0.type == "Étude" }) { studyDates.append(dateStr) } }
        studyDates.sort()
        if let currentIndex = studyDates.firstIndex(of: DateFormatter.yyyyMMdd.string(from: Date())) { return (currentIndex + 1, studyDates.count) }
        return nil
    }
    func getTodaysTodos() -> [(courseName: String, todo: TodoItem, colorHex: String, todoIndex: Int)] {
        var result: [(String, TodoItem, String, Int)] = []
        for (cName, course) in courses {
            if let todos = course.todos {
                for (index, todo) in todos.enumerated() {
                    if let date = todo.dueDate, Calendar.current.isDateInToday(date), !todo.isDone { result.append((cName, todo, course.colorHex, index)) }
                }
            }
        }
        return result
    }
}

// MARK: - EXTENSIONS
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else { return "#000000" }
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(components[0]) * 255), lroundf(Float(components[1]) * 255), lroundf(Float(components[2]) * 255))
    }
}
extension DateFormatter {
    static let yyyyMMdd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
}

// MARK: - MAIN VIEW (Navigation)
struct ContentView: View {
    @StateObject var appData = AppData()
    @State private var selection: String? = "Général"
    @State private var isShowingAddCourse = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Tableau de bord") {
                    NavigationLink("📊 Général", value: "Général")
                    NavigationLink("📅 Planning", value: "Planning")
                    NavigationLink("🎓 Parcours", value: "Parcours")
                }
                let groupedCourses = Dictionary(grouping: appData.courses.keys, by: { appData.courses[$0]?.category ?? "Général" })
                ForEach(groupedCourses.keys.sorted(), id: \.self) { category in
                    Section(category) { ForEach(groupedCourses[category]!.sorted(), id: \.self) { cName in NavigationLink("📚 \(cName)", value: cName) } }
                }
            }
            .listStyle(.sidebar)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button(action: { isShowingAddCourse = true }) { Image(systemName: "plus") }.help("Ajouter un nouveau cours") } }
        } detail: {
            if selection == "Général" { GeneralView(appData: appData) }
            else if selection == "Planning" { PlanningView(appData: appData) }
            else if selection == "Parcours" { ParcoursMainView(appData: appData) }
            else if let courseName = selection, appData.courses.keys.contains(courseName) { CourseDetailView(appData: appData, courseName: courseName, selection: $selection) }
            else { Text("Sélectionne un élément dans le menu").foregroundColor(.secondary) }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $isShowingAddCourse) { AddCourseSheet(appData: appData, isPresented: $isShowingAddCourse) }
    }
}

// MARK: - GENERAL VIEW & CHARTS
struct GeneralView: View {
    @ObservedObject var appData: AppData
    @State private var zoomedItem: GeneralZoomType?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text("📚 Bloc.us - Ton partenaire de blocus").font(.largeTitle).bold()
                    Spacer()
                    if appData.getDisplayStreak() > 0 {
                        HStack(spacing: 4) { Text("🔥"); Text("\(appData.getDisplayStreak()) jours").fontWeight(.bold).foregroundColor(.orange) }
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Color.orange.opacity(0.2)).cornerRadius(20)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("🎯 Focus du jour").font(.title2).bold()
                    let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
                    let todaysEvents = appData.schedule[todayStr] ?? []
                    if todaysEvents.isEmpty {
                        Text("🎉 Rien de prévu au calendrier aujourd'hui. Profite de ton temps libre pour te ressourcer !").padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.green.opacity(0.2)).cornerRadius(8)
                    } else {
                        ForEach(todaysEvents) { ev in
                            if let courseData = appData.courses[ev.course] {
                                VStack(alignment: .leading, spacing: 8) {
                                    if ev.type == "Examen" {
                                        Text("🚨 EXAMEN AUJOURD'HUI : \(ev.course)").font(.headline).foregroundColor(.red)
                                        Text("🕒 Heure : \(courseData.examStartTime) - \(courseData.examEndTime)  |  📍 Lieu : \(courseData.examLocation.isEmpty ? "Non défini" : courseData.examLocation)")
                                        if !ev.description.isEmpty { Text("📝 Détails : \(ev.description)") }
                                    } else {
                                        Text("📚 \(ev.course)").font(.headline)
                                        if !ev.description.isEmpty { Text("🎯 Objectif : \(ev.description)") }
                                        CustomProgressBar(progress: appData.computeProgress(for: ev.course), color: Color(hex: courseData.colorHex), isMain: true)
                                    }
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading).background(ev.type == "Examen" ? Color.red.opacity(0.1) : Color.blue.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 8).stroke(ev.type == "Examen" ? Color.red : Color.blue, lineWidth: 1))
                            }
                        }
                    }
                    
                    let todaysTodos = appData.getTodaysTodos()
                    if !todaysTodos.isEmpty {
                        Text("📝 À faire aujourd'hui").font(.headline).foregroundColor(.orange).padding(.top, 10)
                        ForEach(todaysTodos, id: \.todo.id) { item in
                            HStack {
                                Button(action: { appData.courses[item.courseName]?.todos?[item.todoIndex].isDone = true; appData.registerActivity() }) { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).foregroundColor(.orange)
                                Text(item.todo.text).font(.body)
                                Text("(\(item.courseName))").font(.caption).foregroundColor(Color(hex: item.colorHex))
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                
                Divider()
                Text("Vue d'ensemble de ton blocus").font(.title2).bold()
                
                if appData.courses.isEmpty {
                    Text("Ajoute des cours dans le menu de gauche pour commencer !").foregroundColor(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading) {
                            HStack { Text("Équilibre d'étude").font(.headline); Spacer(); Button(action: { zoomedItem = .equilibre }) { Image(systemName: "plus.magnifyingglass") } }
                            GeneralEquilibreChart(appData: appData).frame(height: 250)
                        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        
                        VStack(alignment: .leading) {
                            HStack { Text("Répartition du temps").font(.headline); Spacer(); Button(action: { zoomedItem = .repartition }) { Image(systemName: "plus.magnifyingglass") } }
                            GeneralRepartitionChart(appData: appData).frame(height: 250)
                        }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack { Text("🎯 Stratégie des points").font(.headline); Spacer(); Button(action: { zoomedItem = .points }) { Image(systemName: "plus.magnifyingglass") } }
                        GeneralPointsChart(appData: appData).frame(height: 250)
                    }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(appData.courses.keys.sorted(), id: \.self) { c in
                            let stats = appData.computeStudyDays(for: c)
                            VStack(alignment: .leading) {
                                Text(c).font(.headline)
                                Text("⏱️ Prévus : \(stats.total) j | ⏳ Restants : \(stats.remaining) j").font(.subheadline).foregroundColor(.secondary)
                                CustomProgressBar(progress: appData.computeProgress(for: c), color: Color(hex: appData.courses[c]!.colorHex), isMain: true)
                            }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        }
                    }
                }
            }.padding()
        }
        .sheet(item: $zoomedItem) { zItem in GeneralZoomModalView(appData: appData, zoomType: zItem) }
    }
}

// Composants Chart Isolés avec HOVER pour la page Général
struct GeneralEquilibreChart: View {
    @ObservedObject var appData: AppData
    @State private var hoveredCourse: String?
    var body: some View {
        VStack {
            if let h = hoveredCourse { Text("\(h) : \(String(format: "%.1f", appData.computeProgress(for: h) * 100)) % accompli").font(.caption).bold().foregroundColor(.blue) }
            else { Text("Survolez pour le détail").font(.caption).foregroundColor(.secondary) }
            
            Chart {
                ForEach(appData.courses.keys.sorted(), id: \.self) { c in
                    BarMark(x: .value("Progression", appData.computeProgress(for: c) * 100), y: .value("Cours", c))
                        .foregroundStyle(Color(hex: appData.courses[c]!.colorHex))
                        .opacity(hoveredCourse == nil || hoveredCourse == c ? 1.0 : 0.4)
                }
            }
            .chartYSelection(value: $hoveredCourse)
            .chartXScale(domain: 0...100)
        }
    }
}

struct GeneralRepartitionChart: View {
    @ObservedObject var appData: AppData
    @State private var hoveredAngle: Double?
    var body: some View {
        let data = appData.courses.keys.map { (name: $0, days: appData.computeStudyDays(for: $0).total) }.filter { $0.days > 0 }
        
        let hoverText: String = {
            guard let angle = hoveredAngle else { return "Survolez pour le détail" }
            var sum: Double = 0
            for item in data {
                sum += Double(item.days)
                if angle <= sum { return "\(item.name) : \(item.days) jour(s)" }
            }
            return " "
        }()
        
        VStack {
            if #available(macOS 14.0, *) {
                Text(hoverText).font(.caption).bold().foregroundColor(hoveredAngle == nil ? .secondary : .blue)
                Chart {
                    ForEach(data, id: \.name) { item in
                        SectorMark(angle: .value("Jours", item.days), innerRadius: .ratio(0.5), angularInset: 1.5)
                            .foregroundStyle(Color(hex: appData.courses[item.name]!.colorHex))
                            .annotation(position: .overlay) { Text("\(item.days)j").font(.caption).bold().foregroundColor(.white) }
                    }
                }.chartAngleSelection(value: $hoveredAngle)
            } else { Text("Nécessite macOS 14+") }
        }
    }
}

struct GeneralPointsChart: View {
    @ObservedObject var appData: AppData
    @State private var hoveredCourse: String?
    var body: some View {
        let data = generateBarData()
        VStack {
            if let h = hoveredCourse {
                let courseData = data.filter { $0.course == h }
                let acq = courseData.first(where: { $0.type == "1. Acquis" })?.points ?? 0
                let aReu = courseData.first(where: { $0.type == "2. À réussir" })?.points ?? 0
                Text("\(h) : \(String(format: "%.1f", acq)) acquis, \(String(format: "%.1f", aReu)) à réussir").font(.caption).bold().foregroundColor(.blue)
            } else { Text("Survolez pour le détail").font(.caption).foregroundColor(.secondary) }
            
            Chart {
                ForEach(data) { item in
                    BarMark(x: .value("Cours", item.course), y: .value("Points", item.points))
                        .foregroundStyle(by: .value("Type", item.type))
                        .opacity(hoveredCourse == nil || hoveredCourse == item.course ? 1.0 : 0.4)
                }
            }
            .chartXSelection(value: $hoveredCourse)
            .chartForegroundStyleScale(["1. Acquis": Color.green, "2. À réussir": Color.orange, "3. Bonus": Color.gray.opacity(0.3)])
            .chartYScale(domain: 0...20)
        }
    }
    struct BarData: Identifiable { let id = UUID(); let course: String; let type: String; let points: Double }
    func generateBarData() -> [BarData] {
        var result: [BarData] = []
        for (cName, d) in appData.courses {
            let target = d.passingGrade
            let earned = d.grading.reduce(0) { $0 + $1.score }
            let totGraded = d.grading.reduce(0) { $0 + $1.total }
            let examTot = max(0, 20 - totGraded)
            let needed = max(0, target - earned)
            let neededExam = min(examTot, needed)
            let bonus = max(0, examTot - neededExam)
            result.append(BarData(course: cName, type: "1. Acquis", points: earned))
            result.append(BarData(course: cName, type: "2. À réussir", points: neededExam))
            result.append(BarData(course: cName, type: "3. Bonus", points: bonus))
        }
        return result
    }
}

struct GeneralZoomModalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appData: AppData
    let zoomType: GeneralZoomType
    var body: some View {
        VStack {
            HStack { Spacer(); Button("Fermer la vue") { dismiss() }.buttonStyle(.borderedProminent) }.padding(.bottom, 10)
            switch zoomType {
            case .equilibre: Text("Équilibre d'étude par cours").font(.title).bold(); GeneralEquilibreChart(appData: appData).padding()
            case .repartition: Text("Répartition du temps alloué par cours").font(.title).bold(); GeneralRepartitionChart(appData: appData).padding()
            case .points: Text("Stratégie des points (sur 20)").font(.title).bold(); GeneralPointsChart(appData: appData).padding()
            }
            Spacer()
        }.padding().frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - PARCOURS MAIN VIEW (Le Hub)
struct ParcoursMainView: View {
    @ObservedObject var appData: AppData
    @State private var selectedTab: String = "Dashboard"
    @State private var isShowingAddYear = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("🎓 Mon Parcours Académique").font(.largeTitle).bold()
                Spacer()
                Button("➕ Ajouter une année") { isShowingAddYear = true }.buttonStyle(.bordered)
            }.padding([.horizontal, .top])
            
            Picker("", selection: $selectedTab) {
                Text("Dashboard Global").tag("Dashboard")
                ForEach(appData.academicYears, id: \.id) { year in Text("\(year.level) (\(year.yearString))").tag(year.id.uuidString) }
            }.pickerStyle(.segmented).padding(.horizontal)
            
            Divider()
            
            if selectedTab == "Dashboard" { ParcoursDashboardView(appData: appData) }
            else if let yearId = UUID(uuidString: selectedTab) { AcademicYearDetailView(appData: appData, yearId: yearId, selectedTab: $selectedTab) }
            Spacer()
        }
        .sheet(isPresented: $isShowingAddYear) { AddAcademicYearSheet(appData: appData, isPresented: $isShowingAddYear, selectedTab: $selectedTab) }
    }
}

// MARK: - PARCOURS DASHBOARD
struct ParcoursDashboardView: View {
    @ObservedObject var appData: AppData
    @State private var zoomedItem: DashboardZoomType?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Vue d'ensemble de tes études").font(.title2).bold()
                if appData.academicYears.isEmpty {
                    Text("Ajoute une année académique pour commencer à tracker ton parcours !").foregroundColor(.secondary)
                } else {
                    let totalCredits = appData.academicYears.reduce(0) { $0 + $1.totalCredits() }
                    let earnedCredits = appData.academicYears.reduce(0) { $0 + $1.totalEarnedCredits() }
                    
                    let totalWeighted = appData.academicYears.reduce(0) { sumYear, year in
                        sumYear + year.courses.reduce(0) { sumCourse, course in
                            sumCourse + (year.bestGrade(for: course.code) * course.credits)
                        }
                    }
                    
                    let globalGPA = totalCredits > 0 ? totalWeighted / totalCredits : 0
                    let totalCoursesCount = appData.academicYears.reduce(0) { $0 + $1.courses.count }
                    
                    HStack(spacing: 20) {
                        RecapCard(title: "Crédits Validés (Toutes années)", value: "\(String(format: "%.1f", earnedCredits)) / \(String(format: "%.1f", totalCredits))", color: .green)
                        RecapCard(title: "Moyenne Globale Pondérée", value: "\(String(format: "%.2f", globalGPA)) / 20", color: .blue)
                        RecapCard(title: "Cours passés", value: "\(totalCoursesCount)", color: .orange)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Évolution de la moyenne annuelle").font(.headline)
                            Spacer()
                            Button(action: { zoomedItem = .chartEvolution }) { Image(systemName: "plus.magnifyingglass") }
                        }
                        DashboardEvolutionChart(appData: appData).frame(height: 250)
                    }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                }
            }.padding()
        }
        .sheet(item: $zoomedItem) { zItem in DashboardZoomModalView(appData: appData, zoomType: zItem) }
    }
}

struct DashboardEvolutionChart: View {
    @ObservedObject var appData: AppData
    @State private var hoveredYear: String?
    var body: some View {
        VStack {
            if let h = hoveredYear, let yId = appData.academicYears.first(where: { $0.yearString == h })?.id, let year = appData.academicYears.first(where: { $0.id == yId }) {
                Text("\(h) : \(String(format: "%.2f", year.weightedGPA())) / 20").font(.caption).bold().foregroundColor(.blue)
            } else { Text("Survolez pour le détail").font(.caption).foregroundColor(.secondary) }
            
            Chart {
                ForEach(appData.academicYears) { year in
                    LineMark(x: .value("Année", year.yearString), y: .value("Moyenne", year.weightedGPA()))
                        .symbol(Circle()).foregroundStyle(Color.blue)
                    if hoveredYear == year.yearString { RuleMark(x: .value("Année", year.yearString)).foregroundStyle(.gray.opacity(0.3)) }
                }
            }
            .chartXSelection(value: $hoveredYear)
            .chartYScale(domain: 0...20)
        }
    }
}

struct DashboardZoomModalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appData: AppData
    let zoomType: DashboardZoomType
    var body: some View {
        VStack {
            HStack { Spacer(); Button("Fermer la vue") { dismiss() }.buttonStyle(.borderedProminent) }.padding(.bottom, 10)
            switch zoomType {
            case .chartEvolution: Text("Évolution de la moyenne annuelle").font(.title).bold(); DashboardEvolutionChart(appData: appData).padding()
            }
            Spacer()
        }.padding().frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - VUE DÉTAILLÉE D'UNE ANNÉE
struct AcademicYearDetailView: View {
    @ObservedObject var appData: AppData
    let yearId: UUID
    @Binding var selectedTab: String
    
    @State private var isShowingAddCourse = false
    @State private var isShowingAddExam = false
    @State private var zoomedItem: ZoomType?
    
    var body: some View {
        if let year = appData.academicYears.first(where: { $0.id == yearId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text(year.level).font(.title).bold()
                            Text("\(year.school) • \(year.yearString)").font(.title3).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { appData.academicYears.removeAll(where: { $0.id == year.id }); selectedTab = "Dashboard" }) {
                            Image(systemName: "trash").foregroundColor(.red); Text("Supprimer l'année").foregroundColor(.red)
                        }.buttonStyle(.bordered)
                    }
                    
                    // RECAP 100% PAE (comme l'ancien code)
                    HStack(spacing: 15) {
                        RecapCard(title: "Crédits Validés sur l'année", value: "\(String(format: "%.1f", year.totalEarnedCredits())) / \(String(format: "%.1f", year.totalCredits()))", color: .green)
                        RecapCard(title: "Moyenne Pondérée (Meilleure note)", value: String(format: "%.2f", year.weightedGPA()), color: .blue)
                        let avgAttempts = year.courses.isEmpty ? 0 : Double(year.courses.reduce(0) { $0 + $1.attempts }) / Double(year.courses.count)
                        RecapCard(title: "Moyenne Tentatives", value: String(format: "%.1f", avgAttempts), color: .orange)
                        RecapCard(title: "Total Cours", value: "\(year.courses.count)", color: .purple)
                    }
                    Divider()
                    
                    HStack {
                        Text("Cours de l'année (PAE)").font(.title2).bold()
                        Spacer()
                        Button(action: { isShowingAddCourse = true }) { HStack { Image(systemName: "plus.circle.fill"); Text("Ajouter un cours") } }.buttonStyle(.borderedProminent)
                    }
                    
                    VStack {
                        HStack { Text("Premier Quadrimestre (Q1)").font(.title3).bold(); Spacer(); Button(action: { zoomedItem = .tableQ1 }) { Image(systemName: "plus.magnifyingglass") } }
                        SemesterTableContent(appData: appData, yearId: year.id, courses: year.courses.filter { $0.semester == "Q1" })
                    }
                    
                    VStack {
                        HStack { Text("Deuxième Quadrimestre (Q2)").font(.title3).bold(); Spacer(); Button(action: { zoomedItem = .tableQ2 }) { Image(systemName: "plus.magnifyingglass") } }
                        SemesterTableContent(appData: appData, yearId: year.id, courses: year.courses.filter { $0.semester == "Q2" })
                    }
                    Text("💡 Astuce : Double-cliquez sur un cours pour le modifier.").font(.caption).foregroundColor(.secondary)
                    
                    Divider()
                    HStack {
                        Text("Sessions d'Examens de l'année").font(.title2).bold()
                        Spacer()
                        Button(action: { isShowingAddExam = true }) { HStack { Image(systemName: "plus.circle.fill"); Text("Ajouter un résultat") } }.buttonStyle(.borderedProminent)
                    }
                    
                    ExamSessionSection(appData: appData, year: year, sessionName: "Janvier", zoomAction: { zoomedItem = .examsJan })
                    ExamSessionSection(appData: appData, year: year, sessionName: "Juin", zoomAction: { zoomedItem = .examsJun })
                    ExamSessionSection(appData: appData, year: year, sessionName: "Août", zoomAction: { zoomedItem = .examsAug })
                    
                    Divider()
                    if !year.courses.isEmpty || !(year.exams ?? []).isEmpty {
                        Text("Analyses de l'année").font(.title2).bold()
                        HStack(alignment: .top, spacing: 20) {
                            if !year.courses.isEmpty {
                                VStack(alignment: .leading) {
                                    HStack { Text("Notes MAX par cours (PAE)").font(.headline); Spacer(); Button(action: { zoomedItem = .chartNotes }) { Image(systemName: "plus.magnifyingglass") } }
                                    NotesChart(year: year).frame(height: 250)
                                }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                                
                                VStack(alignment: .leading) {
                                    HStack { Text("Répartition des Crédits (PAE)").font(.headline); Spacer(); Button(action: { zoomedItem = .chartCat }) { Image(systemName: "plus.magnifyingglass") } }
                                    CategoriesChart(courses: year.courses).frame(height: 250)
                                }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                            }
                        }
                        
                        if !(year.exams ?? []).isEmpty {
                            Text("Résultats graphiques par Session").font(.title2).bold().padding(.top)
                            HStack(alignment: .top, spacing: 15) {
                                let jan = (year.exams ?? []).filter { $0.sessionName == "Janvier" }
                                let jun = (year.exams ?? []).filter { $0.sessionName == "Juin" }
                                let aug = (year.exams ?? []).filter { $0.sessionName == "Août" }
                                
                                if !jan.isEmpty { VStack { HStack { Text("Janvier").font(.headline); Spacer(); Button(action: { zoomedItem = .chartJan }) { Image(systemName: "plus.magnifyingglass") } }; SessionBarChart(appData: appData, exams: jan).frame(height: 200) }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12) }
                                if !jun.isEmpty { VStack { HStack { Text("Juin").font(.headline); Spacer(); Button(action: { zoomedItem = .chartJun }) { Image(systemName: "plus.magnifyingglass") } }; SessionBarChart(appData: appData, exams: jun).frame(height: 200) }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12) }
                                if !aug.isEmpty { VStack { HStack { Text("Août").font(.headline); Spacer(); Button(action: { zoomedItem = .chartAug }) { Image(systemName: "plus.magnifyingglass") } }; SessionBarChart(appData: appData, exams: aug).frame(height: 200) }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(12) }
                            }
                        }
                    }
                }.padding()
            }
            .sheet(isPresented: $isShowingAddCourse) { AddParcoursCourseSheet(appData: appData, isPresented: $isShowingAddCourse, yearId: year.id) }
            .sheet(isPresented: $isShowingAddExam) { AddExamResultSheet(appData: appData, isPresented: $isShowingAddExam, yearId: year.id) }
            .sheet(item: $zoomedItem) { zoomType in ZoomModalView(appData: appData, year: year, zoomType: zoomType) }
        }
    }
}

// MARK: - TABLEAUX ET COMPOSANTS PARCOURS
struct RecapCard: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack { Text(title).font(.caption).foregroundColor(.secondary); Text(value).font(.title2).bold().foregroundColor(color) }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
    }
}

struct SemesterTableContent: View {
    @ObservedObject var appData: AppData
    let yearId: UUID
    let courses: [ParcoursCourse]
    @State private var courseToEdit: ParcoursCourse?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Code").bold().frame(width: 80, alignment: .leading); Text("Nom du Cours").bold().frame(maxWidth: .infinity, alignment: .leading); Text("Crédits").bold().frame(width: 60, alignment: .center); Text("Catégorie").bold().frame(width: 120, alignment: .leading); Text("Note finale /20").bold().frame(width: 100, alignment: .center); Text("Tentatives").bold().frame(width: 80, alignment: .center); Text("").frame(width: 30) }
            .padding(.horizontal, 10).padding(.vertical, 8).background(Color.gray.opacity(0.1))
            
            if courses.isEmpty { Text("Aucun cours encodé.").foregroundColor(.secondary).padding() } else {
                ForEach(courses) { course in
                    HStack {
                        Text(course.code).fontWeight(.semibold).frame(width: 80, alignment: .leading).foregroundColor(.blue)
                        Text(course.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.1f", course.credits)).frame(width: 60, alignment: .center)
                        Text(course.category).frame(width: 120, alignment: .leading).foregroundColor(.secondary)
                        Text(String(format: "%.2f", course.grade)).frame(width: 100, alignment: .center).foregroundColor(course.grade >= 10.0 ? .green : .red).bold()
                        Text("\(course.attempts)").frame(width: 80, alignment: .center)
                        Button(action: { appData.removeParcoursCourse(yearId: yearId, courseId: course.id) }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).frame(width: 30)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle()).onTapGesture(count: 2) { courseToEdit = course }; Divider()
                }
            }
        }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .sheet(item: $courseToEdit) { course in EditParcoursCourseSheet(appData: appData, yearId: yearId, course: course) }
    }
}

struct ExamSessionSection: View {
    @ObservedObject var appData: AppData
    let year: AcademicYear; let sessionName: String; let zoomAction: () -> Void
    var body: some View {
        let exams = (year.exams ?? []).filter { $0.sessionName == sessionName }
        var credits: Double = 0
        for ex in exams where ex.grade >= 10.0 { if let c = appData.getParcoursCourse(code: ex.courseCode) { credits += c.credits } }
        return VStack {
            HStack {
                Text("Session de \(sessionName)").font(.title3).bold(); Spacer()
                Text("Crédits validés à cette session : \(String(format: "%.1f", credits))").font(.subheadline).foregroundColor(.green)
                Button(action: zoomAction) { Image(systemName: "plus.magnifyingglass") }.padding(.leading, 5)
            }
            ExamSessionTableContent(appData: appData, yearId: year.id, exams: exams)
        }
    }
}

struct ExamSessionTableContent: View {
    @ObservedObject var appData: AppData
    let yearId: UUID; let exams: [ExamResult]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Code").bold().frame(width: 100, alignment: .leading); Text("Nom du Cours").bold().frame(maxWidth: .infinity, alignment: .leading); Text("Note /20").bold().frame(width: 100, alignment: .center); Text("Tentative").bold().frame(width: 100, alignment: .center); Text("").frame(width: 30) }.padding(.horizontal, 10).padding(.vertical, 8).background(Color.orange.opacity(0.1))
            if exams.isEmpty { Text("Aucun résultat pour cette session.").foregroundColor(.secondary).padding() } else {
                ForEach(exams) { exam in
                    let cName = appData.getParcoursCourse(code: exam.courseCode)?.name ?? "Inconnu"
                    HStack {
                        Text(exam.courseCode).fontWeight(.semibold).frame(width: 100, alignment: .leading).foregroundColor(.blue)
                        Text(cName).frame(maxWidth: .infinity, alignment: .leading).foregroundColor(.secondary)
                        Text(String(format: "%.2f", exam.grade)).frame(width: 100, alignment: .center).foregroundColor(exam.grade >= 10.0 ? .green : .red).bold()
                        Text("n° \(exam.attempt)").frame(width: 100, alignment: .center)
                        Button(action: { appData.removeExamResult(yearId: yearId, examId: exam.id) }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).frame(width: 30)
                    }.padding(.horizontal, 10).padding(.vertical, 8); Divider()
                }
            }
        }.background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}

// --- Les Graphiques Réutilisables ---

struct NotesChart: View {
    let year: AcademicYear
    @State private var hoveredCourse: String?
    
    var body: some View {
        // LE GRAPH NE MONTRE STRICTEMENT QUE LES COURS DU PAE, MAIS AVEC LEUR MEILLEURE NOTE GLOBALE
        let sortedCourses = year.courses.sorted(by: { $0.code < $1.code })
        
        return VStack {
            if let h = hoveredCourse, let course = year.courses.first(where: { $0.code == h }) {
                let bestG = year.bestGrade(for: course.code)
                Text("\(h) - \(course.name) : \(String(format: "%.2f", bestG)) / 20")
                    .font(.caption).bold().foregroundColor(.blue)
            } else { Text("Survolez pour le détail").font(.caption).foregroundColor(.secondary) }
            
            Chart {
                ForEach(sortedCourses) { c in
                    let bestG = year.bestGrade(for: c.code)
                    BarMark(x: .value("Cours", c.code), y: .value("Note MAX", bestG))
                        .foregroundStyle(bestG >= 10.0 ? Color.blue : Color.red.opacity(0.6))
                        .opacity(hoveredCourse == nil || hoveredCourse == c.code ? 1.0 : 0.4)
                }
            }.chartXSelection(value: $hoveredCourse).chartYScale(domain: 0...20)
        }
    }
}

struct CategoriesChart: View {
    let courses: [ParcoursCourse]
    @State private var hoveredAngle: Double?
    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                let groupedByCat = Dictionary(grouping: courses, by: { $0.category })
                let data = groupedByCat.keys.map { (cat: $0, credits: groupedByCat[$0]!.reduce(0) { $0 + $1.credits }) }.sorted(by: { $0.cat < $1.cat })
                let hoverText: String = {
                    guard let angle = hoveredAngle else { return "Survolez pour le détail" }
                    var sum: Double = 0
                    for item in data { sum += item.credits; if angle <= sum { return "\(item.cat) : \(String(format: "%.1f", item.credits)) cr." } }
                    return " "
                }()
                VStack {
                    Text(hoverText).font(.caption).bold().foregroundColor(hoveredAngle == nil ? .secondary : .blue)
                    Chart {
                        ForEach(data, id: \.cat) { item in
                            SectorMark(angle: .value("Crédits", item.credits), innerRadius: .ratio(0.5), angularInset: 1.5).foregroundStyle(by: .value("Catégorie", item.cat))
                        }
                    }.chartAngleSelection(value: $hoveredAngle)
                }
            } else { Text("Nécessite macOS 14+") }
        }
    }
}

struct SessionBarChart: View {
    @ObservedObject var appData: AppData
    let exams: [ExamResult]
    @State private var hoveredCourse: String?
    var body: some View {
        VStack {
            if let h = hoveredCourse, let exam = exams.first(where: { $0.courseCode == h }) {
                let courseName = appData.getParcoursCourse(code: h)?.name ?? "Cours"
                Text("\(h) - \(courseName) : \(String(format: "%.2f", exam.grade)) / 20").font(.caption).bold().foregroundColor(.blue)
            } else { Text("Survolez pour le détail").font(.caption).foregroundColor(.secondary) }
            
            Chart {
                ForEach(exams) { exam in
                    BarMark(x: .value("Cours", exam.courseCode), y: .value("Note", exam.grade))
                        .foregroundStyle(exam.grade >= 10.0 ? Color.green : Color.red)
                        .opacity(hoveredCourse == nil || hoveredCourse == exam.courseCode ? 1.0 : 0.4)
                }
            }.chartXSelection(value: $hoveredCourse).chartYScale(domain: 0...20)
        }
    }
}

// MARK: - LE MODAL DE ZOOM (LOUPE)
struct ZoomModalView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appData: AppData
    let year: AcademicYear
    let zoomType: ZoomType
    var body: some View {
        VStack {
            HStack { Spacer(); Button("Fermer la vue") { dismiss() }.buttonStyle(.borderedProminent) }.padding(.bottom, 10)
            switch zoomType {
            case .tableQ1: Text("Premier Quadrimestre (Q1)").font(.title).bold(); SemesterTableContent(appData: appData, yearId: year.id, courses: year.courses.filter { $0.semester == "Q1" })
            case .tableQ2: Text("Deuxième Quadrimestre (Q2)").font(.title).bold(); SemesterTableContent(appData: appData, yearId: year.id, courses: year.courses.filter { $0.semester == "Q2" })
            case .examsJan: Text("Résultats Session Janvier").font(.title).bold(); ExamSessionTableContent(appData: appData, yearId: year.id, exams: (year.exams ?? []).filter{ $0.sessionName == "Janvier" })
            case .examsJun: Text("Résultats Session Juin").font(.title).bold(); ExamSessionTableContent(appData: appData, yearId: year.id, exams: (year.exams ?? []).filter{ $0.sessionName == "Juin" })
            case .examsAug: Text("Résultats Session Août").font(.title).bold(); ExamSessionTableContent(appData: appData, yearId: year.id, exams: (year.exams ?? []).filter{ $0.sessionName == "Août" })
            case .chartNotes: Text("Notes MAX par cours (PAE)").font(.title).bold(); NotesChart(year: year).padding()
            case .chartCat: Text("Répartition des crédits").font(.title).bold(); CategoriesChart(courses: year.courses).padding()
            case .chartJan: Text("Notes de la session de Janvier").font(.title).bold(); SessionBarChart(appData: appData, exams: (year.exams ?? []).filter{ $0.sessionName == "Janvier" }).padding()
            case .chartJun: Text("Notes de la session de Juin").font(.title).bold(); SessionBarChart(appData: appData, exams: (year.exams ?? []).filter{ $0.sessionName == "Juin" }).padding()
            case .chartAug: Text("Notes de la session d'Août").font(.title).bold(); SessionBarChart(appData: appData, exams: (year.exams ?? []).filter{ $0.sessionName == "Août" }).padding()
            }
            Spacer()
        }.padding().frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - FORMULAIRES PARCOURS
struct AddAcademicYearSheet: View {
    @ObservedObject var appData: AppData
    @Binding var isPresented: Bool
    @Binding var selectedTab: String
    @State private var newYearString = ""
    @State private var newLevel = ""
    @State private var newSchool = ""
    var body: some View {
        VStack(spacing: 20) {
            Text("Nouvelle Année Académique").font(.headline)
            TextField("Année (ex: 2021-2022)", text: $newYearString).textFieldStyle(.roundedBorder)
            TextField("Niveau (ex: Bac 1, Master 2)", text: $newLevel).textFieldStyle(.roundedBorder)
            TextField("École / Unif (ex: UCLouvain)", text: $newSchool).textFieldStyle(.roundedBorder)
            HStack {
                Button("Annuler") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ajouter") {
                    if !newYearString.isEmpty && !newLevel.isEmpty {
                        let newYear = AcademicYear(yearString: newYearString, level: newLevel, school: newSchool, courses: [], exams: [])
                        appData.academicYears.append(newYear)
                        selectedTab = newYear.id.uuidString; isPresented = false
                    }
                }.buttonStyle(.borderedProminent).disabled(newYearString.isEmpty || newLevel.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 300)
    }
}

struct AddParcoursCourseSheet: View {
    @ObservedObject var appData: AppData
    @Binding var isPresented: Bool
    let yearId: UUID
    @State private var code = ""; @State private var name = ""; @State private var credits: Double = 5.0
    @State private var category = ""; @State private var grade: Double = 10.0; @State private var attempts: Int = 1; @State private var semester = "Q1"
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Ajouter un cours au bilan").font(.headline).frame(maxWidth: .infinity, alignment: .center)
            HStack { TextField("Code (ex: LINFO1101)", text: $code).textFieldStyle(.roundedBorder); Picker("", selection: $semester) { ForEach(["Q1", "Q2"], id: \.self) { Text($0) } }.frame(width: 80) }
            TextField("Nom complet du cours", text: $name).textFieldStyle(.roundedBorder)
            TextField("Catégorie (ex: Informatique, Langues...)", text: $category).textFieldStyle(.roundedBorder)
            HStack { VStack(alignment: .leading) { Text("Crédits (ECTS)").font(.caption); TextField("", value: $credits, format: .number).textFieldStyle(.roundedBorder) }; VStack(alignment: .leading) { Text("Note Finale (/20)").font(.caption); TextField("", value: $grade, format: .number).textFieldStyle(.roundedBorder) }; VStack(alignment: .leading) { Text("Tentatives").font(.caption); Stepper("\(attempts)", value: $attempts, in: 1...10) } }
            HStack { Button("Annuler") { isPresented = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Enregistrer") { if !code.isEmpty && !name.isEmpty { appData.addParcoursCourse(yearId: yearId, course: ParcoursCourse(code: code, name: name, credits: credits, category: category, grade: grade, attempts: attempts, semester: semester)); isPresented = false } }.buttonStyle(.borderedProminent).disabled(code.isEmpty || name.isEmpty).keyboardShortcut(.defaultAction) }.padding(.top, 10)
        }.padding().frame(width: 400)
    }
}

struct EditParcoursCourseSheet: View {
    @ObservedObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    let yearId: UUID
    let course: ParcoursCourse
    @State private var code: String; @State private var name: String; @State private var credits: Double; @State private var category: String; @State private var grade: Double; @State private var attempts: Int; @State private var semester: String
    
    init(appData: AppData, yearId: UUID, course: ParcoursCourse) {
        self.appData = appData; self.yearId = yearId; self.course = course
        _code = State(initialValue: course.code); _name = State(initialValue: course.name); _credits = State(initialValue: course.credits); _category = State(initialValue: course.category); _grade = State(initialValue: course.grade); _attempts = State(initialValue: course.attempts); _semester = State(initialValue: course.semester)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Modifier le cours").font(.headline).frame(maxWidth: .infinity, alignment: .center)
            HStack { TextField("Code", text: $code).textFieldStyle(.roundedBorder); Picker("", selection: $semester) { ForEach(["Q1", "Q2"], id: \.self) { Text($0) } }.frame(width: 80) }
            TextField("Nom complet", text: $name).textFieldStyle(.roundedBorder); TextField("Catégorie", text: $category).textFieldStyle(.roundedBorder)
            HStack { VStack(alignment: .leading) { Text("Crédits").font(.caption); TextField("", value: $credits, format: .number).textFieldStyle(.roundedBorder) }; VStack(alignment: .leading) { Text("Note (/20)").font(.caption); TextField("", value: $grade, format: .number).textFieldStyle(.roundedBorder) }; VStack(alignment: .leading) { Text("Tentatives").font(.caption); Stepper("\(attempts)", value: $attempts, in: 1...10) } }
            HStack { Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Sauvegarder") { if !code.isEmpty && !name.isEmpty { var c = course; c.code = code; c.name = name; c.credits = credits; c.category = category; c.grade = grade; c.attempts = attempts; c.semester = semester; appData.updateParcoursCourse(yearId: yearId, course: c); dismiss() } }.buttonStyle(.borderedProminent).disabled(code.isEmpty || name.isEmpty).keyboardShortcut(.defaultAction) }.padding(.top, 10)
        }.padding().frame(width: 400)
    }
}

// LIEN INTER-ANNÉES : Ajout d'examen avec Picker sur TOUS les cours du parcours
struct AddExamResultSheet: View {
    @ObservedObject var appData: AppData
    @Binding var isPresented: Bool
    let yearId: UUID
    @State private var sessionName = "Janvier"; @State private var courseCode = ""; @State private var grade: Double = 10.0; @State private var attempt: Int = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Ajouter un résultat d'examen").font(.headline).frame(maxWidth: .infinity, alignment: .center)
            Picker("Session", selection: $sessionName) { ForEach(["Janvier", "Juin", "Août"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            
            // Le Picker intelligent qui lie Exam et Cours de toutes les années confondues
            VStack(alignment: .leading) {
                Text("Quel cours as-tu passé ?").font(.caption)
                Picker("", selection: $courseCode) {
                    Text("Sélectionne un cours").tag("")
                    ForEach(appData.allParcoursCourses()) { c in Text("\(c.code) - \(c.name)").tag(c.code) }
                }.pickerStyle(.menu).padding(5).background(Color(NSColor.controlBackgroundColor)).cornerRadius(5)
            }
            
            HStack { VStack(alignment: .leading) { Text("Note Obtenue (/20)").font(.caption); TextField("", value: $grade, format: .number).textFieldStyle(.roundedBorder) }; VStack(alignment: .leading) { Text("Quantième tentative ?").font(.caption); Stepper("\(attempt)", value: $attempt, in: 1...10) } }
            HStack { Button("Annuler") { isPresented = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Ajouter") { if !courseCode.isEmpty { appData.addExamResult(yearId: yearId, exam: ExamResult(sessionName: sessionName, courseCode: courseCode, grade: grade, attempt: attempt)); isPresented = false } }.buttonStyle(.borderedProminent).disabled(courseCode.isEmpty).keyboardShortcut(.defaultAction) }.padding(.top, 10)
        }.padding().frame(width: 400)
    }
}

// MARK: - AUTRES VUES EXISTANTES (Général, Planning, Detail Cours)

struct AddCourseSheet: View {
    @ObservedObject var appData: AppData
    @Binding var isPresented: Bool
    @State private var newCourseName = ""; @State private var newCourseCategory = "Général"; @State private var newCourseColor = Color.green
    var body: some View {
        VStack(spacing: 20) {
            Text("Ajouter un nouveau cours").font(.headline); TextField("Acronyme (ex: LINFO2365)", text: $newCourseName).textFieldStyle(.roundedBorder); TextField("Catégorie (ex: Tronc commun)", text: $newCourseCategory).textFieldStyle(.roundedBorder); ColorPicker("Couleur du cours", selection: $newCourseColor)
            HStack { Button("Annuler") { isPresented = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Ajouter") { if !newCourseName.isEmpty && appData.courses[newCourseName] == nil { appData.courses[newCourseName] = Course(colorHex: newCourseColor.toHex(), tasks: [], grading: [], todos: [], links: [], passingGrade: 10.0, fullName: "", professor: "", examStartTime: "08:30", examEndTime: "10:30", examLocation: "", category: newCourseCategory); isPresented = false } }.buttonStyle(.borderedProminent).disabled(newCourseName.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding().frame(width: 300)
    }
}

struct CustomProgressBar: View {
    var progress: Double; var color: Color; var isMain: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(height: isMain ? 24 : 14); RoundedRectangle(cornerRadius: 8).fill(color).frame(width: max(0, min(geometry.size.width * CGFloat(progress), geometry.size.width)), height: isMain ? 24 : 14).animation(.spring(), value: progress) } }.frame(height: isMain ? 24 : 14); Text("\(String(format: "%.2f", progress * 100)) % accompli").font(isMain ? .body : .caption).fontWeight(isMain ? .bold : .regular).foregroundColor(.secondary)
        }
    }
}

struct PlanningView: View {
    @ObservedObject var appData: AppData
    @State private var selectedDate = Date(); @State private var selectedType = "Étude"; @State private var selectedCourse = ""; @State private var eventDesc = ""
    let types = ["Étude", "Examen"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Programme d'étude").font(.largeTitle).bold(); Spacer(); Button("🗑️ Vider TOUT le calendrier") { appData.schedule.removeAll() }.buttonStyle(.bordered) }
                GroupBox("➕ Planifier une session") { HStack(alignment: .bottom) { VStack(alignment: .leading) { Text("Date"); DatePicker("", selection: $selectedDate, displayedComponents: .date).labelsHidden() }; VStack(alignment: .leading) { Text("Type"); Picker("", selection: $selectedType) { ForEach(types, id: \.self) { Text($0) } }.labelsHidden() }; VStack(alignment: .leading) { Text("Cours"); Picker("", selection: $selectedCourse) { Text("Sélectionner").tag(""); ForEach(appData.courses.keys.sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden() }; VStack(alignment: .leading) { Text("Description (Optionnel)"); TextField("Ex: Chapitre 5", text: $eventDesc) }; Button("Ajouter") { if !selectedCourse.isEmpty { appData.addScheduleEvent(date: selectedDate, type: selectedType, course: selectedCourse, description: eventDesc); eventDesc = "" } }.buttonStyle(.borderedProminent).disabled(selectedCourse.isEmpty) }.padding(5) }
                Divider()
                let today = Date(); let calendar = Calendar.current; let currentMonth = calendar.component(.month, from: today); let currentYear = calendar.component(.year, from: today); let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: today)!; let nextMonth = calendar.component(.month, from: nextMonthDate); let nextYear = calendar.component(.year, from: nextMonthDate)
                MonthCalendarView(appData: appData, year: currentYear, month: currentMonth); MonthCalendarView(appData: appData, year: nextYear, month: nextMonth)
            }.padding()
        }
    }
}

struct MonthCalendarView: View {
    @ObservedObject var appData: AppData
    let year: Int; let month: Int
    let daysOfWeek = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(monthName(month)) \(String(year))").font(.title2).bold().padding(.top)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(daysOfWeek, id: \.self) { d in Text(d).bold().frame(maxWidth: .infinity, alignment: .center) }
                let days = getDaysArray()
                ForEach(0..<days.count, id: \.self) { i in if let dayNum = days[i] { CalendarCell(appData: appData, dayNum: dayNum, dateStr: String(format: "%04d-%02d-%02d", year, month, dayNum)) } else { Color.clear.frame(maxWidth: .infinity, minHeight: 120) } }
            }
        }
    }
    func getDaysArray() -> [Int?] { var days: [Int?] = []; let components = DateComponents(year: year, month: month, day: 1); guard let firstOfMonth = Calendar.current.date(from: components) else { return [] }; let range = Calendar.current.range(of: .day, in: .month, for: firstOfMonth)!; let numDays = range.count; var firstWeekday = Calendar.current.component(.weekday, from: firstOfMonth); firstWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1; for _ in 1..<firstWeekday { days.append(nil) }; for d in 1...numDays { days.append(d) }; return days }
    func monthName(_ m: Int) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); return formatter.monthSymbols[m - 1].capitalized }
}

struct CalendarCell: View {
    @ObservedObject var appData: AppData
    let dayNum: Int; let dateStr: String
    var body: some View {
        let isToday = dateStr == DateFormatter.yyyyMMdd.string(from: Date())
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(dayNum)").bold().foregroundColor(isToday ? .white : .primary).padding(6).background(isToday ? Color.red : Color.clear).clipShape(Circle()).padding([.top, .trailing], 5)
            if let events = appData.schedule[dateStr] { ForEach(events) { ev in let colorHex = appData.courses[ev.course]?.colorHex ?? "#4CAF50"; let isExam = ev.type == "Examen"; HStack { Text(isExam ? "🚨 EXAM: \(ev.course)" : "📚 \(ev.course)").font(.system(size: 10, weight: isExam ? .heavy : .medium)).foregroundColor(.primary).lineLimit(1); Spacer(); Button(action: { appData.removeScheduleEvent(dateStr: dateStr, eventId: ev.id) }) { Image(systemName: "trash").font(.system(size: 9)) }.buttonStyle(.plain) }.padding(4).background(Color(hex: colorHex).opacity(0.3)).overlay(Rectangle().frame(width: 4).foregroundColor(Color(hex: colorHex)), alignment: .leading).cornerRadius(4).padding(.horizontal, 2) } }
            Spacer()
        }.frame(maxWidth: .infinity, minHeight: 120, alignment: .topTrailing).background(Color(NSColor.controlBackgroundColor)).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(isToday ? Color.red.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: isToday ? 2 : 1))
    }
}

struct CourseDetailView: View {
    @ObservedObject var appData: AppData
    let courseName: String
    @Binding var selection: String?
    @State private var newTaskName = ""; @State private var newTaskTotal: Double = 1.0; @State private var newGradeName = ""; @State private var newGradeTotal: Double = 20.0; @State private var newGradeScore: Double = 0.0; @State private var editedAcronym = ""; @State private var newTodoText = ""; @State private var newTodoHasDate = false; @State private var newTodoDate = Date(); @State private var newLinkName = ""; @State private var newLinkUrl = ""
    var body: some View {
        if let course = appData.courses[courseName] {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { VStack(alignment: .leading) { Text(courseName).font(.largeTitle).bold(); if !course.fullName.isEmpty { Text(course.fullName).font(.title3) }; if !course.professor.isEmpty { Text("Professeur : \(course.professor)").italic() } }; Spacer(); Button("❌ Supprimer le cours", role: .destructive) { appData.courses.removeValue(forKey: courseName); selection = "Général" }.buttonStyle(.bordered) }
                    CustomProgressBar(progress: appData.computeProgress(for: courseName), color: Color(hex: course.colorHex), isMain: true)
                    DisclosureGroup("⚙️ Paramètres du cours") { VStack(alignment: .leading, spacing: 15) { HStack(alignment: .bottom) { VStack(alignment: .leading) { Text("Acronyme (Nom du cours)"); TextField("Ex: LINFO", text: $editedAcronym).textFieldStyle(.roundedBorder) }; if editedAcronym != courseName && !editedAcronym.isEmpty { Button("Renommer") { appData.renameCourse(oldName: courseName, newName: editedAcronym); selection = editedAcronym }.buttonStyle(.borderedProminent) } }; HStack { VStack(alignment: .leading) { Text("Nom complet"); TextField("Ex: Algorithmique", text: binding(for: \.fullName)) }; VStack(alignment: .leading) { Text("Professeur"); TextField("Ex: John Doe", text: binding(for: \.professor)) } }; HStack { VStack(alignment: .leading) { Text("Catégorie (Section)"); TextField("Ex: Tronc commun", text: Binding(get: { course.category ?? "Général" }, set: { appData.courses[courseName]?.category = $0.isEmpty ? nil : $0 })) }; VStack(alignment: .leading) { Text("Couleur"); ColorPicker("", selection: Binding(get: { Color(hex: course.colorHex) }, set: { appData.courses[courseName]?.colorHex = $0.toHex() })).labelsHidden() }; VStack(alignment: .leading) { Text("Cote cible (/20)"); TextField("", value: binding(for: \.passingGrade), format: .number).frame(width: 60) } }; Text("Informations sur l'examen").bold(); HStack { VStack(alignment: .leading) { Text("Début (HH:MM)"); TextField("", text: binding(for: \.examStartTime)).frame(width: 80) }; VStack(alignment: .leading) { Text("Fin (HH:MM)"); TextField("", text: binding(for: \.examEndTime)).frame(width: 80) }; VStack(alignment: .leading) { Text("Lieu"); TextField("", text: binding(for: \.examLocation)) } } }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(8) }.onAppear { editedAcronym = courseName }.onChange(of: courseName) { newValue in editedAcronym = newValue }
                    DisclosureGroup("🔗 Liens Rapides") { VStack(alignment: .leading) { HStack { TextField("Nom (ex: Dossier Drive)", text: $newLinkName).textFieldStyle(.roundedBorder); TextField("Lien URL", text: $newLinkUrl).textFieldStyle(.roundedBorder); Button("Ajouter") { if !newLinkName.isEmpty && !newLinkUrl.isEmpty { var safeUrl = newLinkUrl; if !safeUrl.lowercased().hasPrefix("http") { safeUrl = "https://" + safeUrl }; var currentLinks = appData.courses[courseName]?.links ?? []; currentLinks.append(LinkItem(name: newLinkName, url: safeUrl)); appData.courses[courseName]?.links = currentLinks; newLinkName = ""; newLinkUrl = "" } }.buttonStyle(.borderedProminent) }; let links = course.links ?? []; if links.isEmpty { Text("Aucun lien ajouté.").foregroundColor(.secondary).padding(.top, 5) } else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { ForEach(Array(links.enumerated()), id: \.element.id) { index, link in HStack { Image(systemName: "link").foregroundColor(.blue); if let url = URL(string: link.url) { Link(link.name, destination: url).foregroundColor(.blue).lineLimit(1) } else { Text(link.name) }; Spacer(); Button("❌") { appData.courses[courseName]?.links?.remove(at: index) }.foregroundColor(.red).buttonStyle(.plain) }.padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1)) } }.padding(.top, 10) } } }
                    Divider()
                    Text("Tâches").font(.title2).bold(); HStack { TextField("Nom (ex: Chapitre 1)", text: $newTaskName); Text("Total :"); TextField("", value: $newTaskTotal, format: .number).frame(width: 50); Button("Ajouter") { if !newTaskName.isEmpty { appData.courses[courseName]?.tasks.append(TaskItem(name: newTaskName, total: newTaskTotal, done: 0)); newTaskName = "" } }.buttonStyle(.borderedProminent) }
                    ForEach(Array(course.tasks.enumerated()), id: \.element.id) { index, task in VStack(alignment: .leading) { Text(task.name).font(.headline); CustomProgressBar(progress: task.total > 0 ? task.done / task.total : 0, color: Color(hex: course.colorHex), isMain: false); HStack { Text("\(String(format: "%.2f", task.done)) / \(String(format: "%.2f", task.total))"); Spacer(); Button("➖") { if task.done > 0 { appData.courses[courseName]?.tasks[index].done -= 1 } }; Button("➕") { if task.done < task.total { appData.courses[courseName]?.tasks[index].done += 1; appData.registerActivity() } }; Button("❌") { appData.courses[courseName]?.tasks.remove(at: index) }.foregroundColor(.red) } }.padding(.bottom, 10) }
                    Divider(); Text("🗓️ Planification").font(.title2).bold(); let stats = appData.computeStudyDays(for: courseName); Text("⏱️ Total prévu : \(stats.total) jour(s)  |  ⏳ Reste à faire : \(stats.remaining) jour(s)"); let plannedDates = getPlannedDates(for: courseName); if plannedDates.isEmpty { Text("- Aucun jour planifié dans le calendrier pour l'instant.") } else { ForEach(plannedDates, id: \.dateStr) { item in Text(item.isExam ? "- 🚨 **\(item.formatted)** (Examen)\(item.desc)" : "- 📚 \(item.formatted)\(item.desc)") } }
                    Divider(); Text("🎓 Cotation").font(.title2).bold(); HStack { TextField("Nom (ex: TP1)", text: $newGradeName); Text("Score :"); TextField("", value: $newGradeScore, format: .number).frame(width: 50); Text("Sur :"); TextField("", value: $newGradeTotal, format: .number).frame(width: 50); Button("Ajouter") { if !newGradeName.isEmpty { appData.courses[courseName]?.grading.append(GradingItem(name: newGradeName, total: newGradeTotal, score: newGradeScore)); newGradeName = "" } }.buttonStyle(.borderedProminent) }
                    ForEach(Array(course.grading.enumerated()), id: \.element.id) { index, grade in HStack { Text("**\(grade.name)**").frame(width: 150, alignment: .leading); TextField("Score", value: Binding(get: { grade.score }, set: { appData.courses[courseName]?.grading[index].score = $0 }), format: .number).textFieldStyle(.roundedBorder).frame(width: 60); Text("/ \(String(format: "%.2f", grade.total)) pts").frame(width: 80, alignment: .leading); Text("\(String(format: "%.2f", (grade.total > 0 ? (grade.score / grade.total) : 0) * 100)) %").frame(width: 80, alignment: .trailing); Spacer(); Button("❌") { appData.courses[courseName]?.grading.remove(at: index) }.foregroundColor(.red) }.padding(.vertical, 4) }
                    Divider(); let (examTotal, needed) = computeExamTarget(grading: course.grading, target: course.passingGrade); Text("🧪 Examen (Cible: \(String(format: "%.2f", course.passingGrade))/20)").font(.title2).bold(); Text("Examen sur **\(String(format: "%.2f", examTotal)) points**"); if examTotal > 0 { let percentage = (needed / examTotal) * 100; Text("🎯 Tu dois avoir **\(String(format: "%.2f", needed)) / \(String(format: "%.2f", examTotal))** pour atteindre ton objectif (\(String(format: "%.1f", percentage))%)") } else { Text("🎉 Objectif déjà atteint ou dépassé avec la cotation continue !").foregroundColor(.green).bold() }
                    Divider(); Text("📝 À faire (TODO)").font(.title2).bold(); HStack { TextField("Nouvelle tâche (ex: Imprimer syllabus)...", text: $newTodoText).textFieldStyle(.roundedBorder); Toggle("Avec date", isOn: $newTodoHasDate); if newTodoHasDate { DatePicker("", selection: $newTodoDate).labelsHidden() }; Button("Ajouter") { if !newTodoText.isEmpty { var currentTodos = appData.courses[courseName]?.todos ?? []; currentTodos.append(TodoItem(text: newTodoText, dueDate: newTodoHasDate ? newTodoDate : nil)); appData.courses[courseName]?.todos = currentTodos; newTodoText = ""; newTodoHasDate = false } }.buttonStyle(.borderedProminent) }
                    let todos = course.todos ?? []; if todos.isEmpty { Text("Aucune tâche en attente.").foregroundColor(.secondary).padding(.vertical, 5) } else { ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in HStack { Button(action: { appData.courses[courseName]?.todos?[index].isDone.toggle(); if appData.courses[courseName]?.todos?[index].isDone == true { appData.registerActivity() } }) { Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle").foregroundColor(todo.isDone ? .green : .gray).font(.title3) }.buttonStyle(.plain); TextField("Tâche", text: Binding(get: { todo.text }, set: { appData.courses[courseName]?.todos?[index].text = $0 })).strikethrough(todo.isDone).foregroundColor(todo.isDone ? .secondary : .primary); if todo.dueDate != nil { DatePicker("", selection: Binding(get: { todo.dueDate ?? Date() }, set: { appData.courses[courseName]?.todos?[index].dueDate = $0 })).labelsHidden() } else { Button(action: { appData.courses[courseName]?.todos?[index].dueDate = Date() }) { Image(systemName: "calendar.badge.plus").foregroundColor(.blue) }.buttonStyle(.plain).help("Ajouter une date") }; Spacer(); Button("❌") { appData.courses[courseName]?.todos?.remove(at: index) }.foregroundColor(.red) }.padding(.vertical, 6).padding(.horizontal, 10).background(Color(NSColor.controlBackgroundColor)).cornerRadius(6) } }
                }.padding()
            }
        }
    }
    func binding<T>(for keyPath: WritableKeyPath<Course, T>) -> Binding<T> { Binding(get: { appData.courses[courseName]![keyPath: keyPath] }, set: { appData.courses[courseName]?[keyPath: keyPath] = $0 }) }
    func getPlannedDates(for course: String) -> [(dateStr: String, formatted: String, isExam: Bool, desc: String)] { var results: [(String, String, Bool, String)] = []; let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); formatter.dateFormat = "d MMM yyyy"; for (dateStr, events) in appData.schedule { for ev in events where ev.course == course { if let d = DateFormatter.yyyyMMdd.date(from: dateStr) { let descText = ev.description.isEmpty ? "" : " *(Objectif: \(ev.description))*"; results.append((dateStr, formatter.string(from: d), ev.type == "Examen", descText)) } } }; return results.sorted(by: { $0.0 < $1.0 }) }
    func computeExamTarget(grading: [GradingItem], target: Double) -> (Double, Double) { let totalPoints = grading.reduce(0) { $0 + $1.total }; let earnedPoints = grading.reduce(0) { $0 + $1.score }; let examTotal = max(0, 20 - totalPoints); let neededExam = target - earnedPoints; return (examTotal, max(0, neededExam)) }
}

struct MenuBarView: View {
    @ObservedObject var appData: AppData
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("🎯 Focus du jour").font(.headline); Spacer(); if appData.getDisplayStreak() > 0 { Text("🔥 \(appData.getDisplayStreak())j").font(.caption).fontWeight(.bold).foregroundColor(.orange).padding(.horizontal, 8).padding(.vertical, 2).background(Color.orange.opacity(0.2)).cornerRadius(10) } }.padding(.bottom, 5)
                let todayStr = DateFormatter.yyyyMMdd.string(from: Date()); let todaysEvents = appData.schedule[todayStr] ?? []
                if todaysEvents.isEmpty { Text("Rien de prévu aujourd'hui ! Profite de ton repos.").font(.subheadline).foregroundColor(.secondary) } else { ForEach(todaysEvents) { ev in if let course = appData.courses[ev.course] { VStack(alignment: .leading, spacing: 8) { HStack { Text("📚 **\(ev.course)**"); Spacer(); if let dayInfo = appData.currentStudyDayInfo(for: ev.course) { Text("Jour \(dayInfo.current)/\(dayInfo.total)").font(.caption).fontWeight(.bold).padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: course.colorHex).opacity(0.2)).foregroundColor(Color(hex: course.colorHex)).cornerRadius(4) } }; if !ev.description.isEmpty { Text("👉 \(ev.description)").font(.caption).foregroundColor(.secondary) }; CustomProgressBar(progress: appData.computeProgress(for: ev.course), color: Color(hex: course.colorHex), isMain: false); let totalPoints = course.grading.reduce(0) { $0 + $1.total }; let earnedPoints = course.grading.reduce(0) { $0 + $1.score }; let examTotal = max(0, 20 - totalPoints); let neededExam = max(0, course.passingGrade - earnedPoints); if examTotal > 0 { let percentage = (neededExam / examTotal) * 100; Text("Objectif examen : **\(String(format: "%.2f", neededExam)) / \(String(format: "%.2f", examTotal))** (\(String(format: "%.1f", percentage))%)").font(.caption2).foregroundColor(.secondary) } else { Text("🎉 Cours déjà validé !").font(.caption2).foregroundColor(.green) } }.padding(10).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8) } } }
                let todaysTodos = appData.getTodaysTodos(); if !todaysTodos.isEmpty { Divider(); Text("📝 À faire aujourd'hui").font(.headline).foregroundColor(.orange); ForEach(todaysTodos, id: \.todo.id) { item in HStack { Button(action: { appData.courses[item.courseName]?.todos?[item.todoIndex].isDone = true; appData.registerActivity() }) { Image(systemName: "circle") }.buttonStyle(.plain); VStack(alignment: .leading) { Text(item.todo.text).font(.subheadline); Text(item.courseName).font(.caption2).foregroundColor(Color(hex: item.colorHex)) } } } }
                Divider(); Text("📚 Progression par section").font(.headline).padding(.top, 5)
                let grouped = Dictionary(grouping: appData.courses.keys, by: { appData.courses[$0]?.category ?? "Général" })
                ForEach(grouped.keys.sorted(), id: \.self) { cat in Text(cat).font(.caption).foregroundColor(.secondary).padding(.top, 5); ForEach(grouped[cat]!.sorted(), id: \.self) { cName in let course = appData.courses[cName]!; HStack { Text(cName).font(.subheadline); Spacer(); Text("\(String(format: "%.2f", appData.computeProgress(for: cName) * 100)) %").font(.caption2) }; CustomProgressBar(progress: appData.computeProgress(for: cName), color: Color(hex: course.colorHex), isMain: false) } }
                Divider(); HStack { Spacer(); Button("Quitter Bloc.us") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundColor(.secondary) }
            }.padding()
        }.frame(width: 330, height: 480)
    }
}
