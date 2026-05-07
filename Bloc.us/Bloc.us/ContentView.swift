import SwiftUI
import Charts
import Foundation
import Combine

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

struct Course: Codable {
    var colorHex: String
    var tasks: [TaskItem]
    var grading: [GradingItem]
    var todos: [TodoItem]?
    var passingGrade: Double
    var fullName: String
    var professor: String
    var examStartTime: String
    var examEndTime: String
    var examLocation: String
    var category: String?
}

// MARK: - VIEW MODEL (Auto-Save)
class AppData: ObservableObject {
    @Published var courses: [String: Course] = [:] {
        didSet { save() }
    }
    @Published var schedule: [String: [CourseEvent]] = [:] {
        didSet { save() }
    }
    
    init() {
        load()
    }
    
    func save() {
        if let encodedCourses = try? JSONEncoder().encode(courses) {
            UserDefaults.standard.set(encodedCourses, forKey: "courses")
        }
        if let encodedSchedule = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(encodedSchedule, forKey: "schedule")
        }
    }
    
    func load() {
        let rawCourses = UserDefaults.standard.data(forKey: "courses")
        let rawSchedule = UserDefaults.standard.data(forKey: "schedule")
        
        if let data = rawCourses, let decoded = try? JSONDecoder().decode([String: Course].self, from: data) {
            self.courses = decoded
        }
        
        if let data = rawSchedule, let decoded = try? JSONDecoder().decode([String: [CourseEvent]].self, from: data) {
            self.schedule = decoded
        }
    }
    
    // --- GESTION DU NOM DU COURS ---
    func renameCourse(oldName: String, newName: String) {
        guard !newName.isEmpty, oldName != newName, courses[newName] == nil, let course = courses[oldName] else { return }
        
        courses[newName] = course
        courses.removeValue(forKey: oldName)
        
        for (date, events) in schedule {
            var updatedEvents = events
            for i in 0..<updatedEvents.count {
                if updatedEvents[i].course == oldName {
                    updatedEvents[i].course = newName
                }
            }
            schedule[date] = updatedEvents
        }
        save()
    }
    
    // --- GESTION ROBUSTE DU CALENDRIER ---
    func addScheduleEvent(date: Date, type: String, course: String, description: String) {
        let dStr = DateFormatter.yyyyMMdd.string(from: date)
        let ev = CourseEvent(type: type, course: course, description: description)
        
        var currentEvents = schedule[dStr] ?? []
        currentEvents.append(ev)
        schedule[dStr] = currentEvents
        save()
    }
    
    func removeScheduleEvent(dateStr: String, eventId: UUID) {
        if var currentEvents = schedule[dateStr] {
            currentEvents.removeAll(where: { $0.id == eventId })
            if currentEvents.isEmpty {
                schedule.removeValue(forKey: dateStr)
            } else {
                schedule[dateStr] = currentEvents
            }
            save()
        }
    }
    
    // --- UTILITAIRES ---
    func computeProgress(for course: String) -> Double {
        guard let c = courses[course] else { return 0 }
        let totalDone = c.tasks.reduce(0) { $0 + $1.done }
        let totalPossible = c.tasks.reduce(0) { $0 + $1.total }
        return totalPossible > 0 ? totalDone / totalPossible : 0
    }
    
    func computeStudyDays(for course: String) -> (total: Int, remaining: Int) {
        let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
        var total = 0
        var remaining = 0
        
        for (dateStr, events) in schedule {
            for ev in events where ev.course == course && ev.type == "Étude" {
                total += 1
                if dateStr >= todayStr { remaining += 1 }
            }
        }
        return (total, remaining)
    }
    
    func currentStudyDayInfo(for course: String) -> (current: Int, total: Int)? {
        var studyDates: [String] = []
        for (dateStr, events) in schedule {
            if events.contains(where: { $0.course == course && $0.type == "Étude" }) {
                studyDates.append(dateStr)
            }
        }
        studyDates.sort()
        let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
        if let currentIndex = studyDates.firstIndex(of: todayStr) {
            return (currentIndex + 1, studyDates.count)
        }
        return nil
    }
    
    func getTodaysTodos() -> [(courseName: String, todo: TodoItem, colorHex: String, todoIndex: Int)] {
        var result: [(String, TodoItem, String, Int)] = []
        for (cName, course) in courses {
            if let todos = course.todos {
                for (index, todo) in todos.enumerated() {
                    if let date = todo.dueDate, Calendar.current.isDateInToday(date), !todo.isDone {
                        result.append((cName, todo, course.colorHex, index))
                    }
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
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
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
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
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
                }
                
                let groupedCourses = Dictionary(grouping: appData.courses.keys, by: { appData.courses[$0]?.category ?? "Général" })
                ForEach(groupedCourses.keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(groupedCourses[category]!.sorted(), id: \.self) { cName in
                            NavigationLink("📚 \(cName)", value: cName)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isShowingAddCourse = true }) { Image(systemName: "plus") }
                    .help("Ajouter un nouveau cours")
                }
            }
        } detail: {
            if selection == "Général" {
                GeneralView(appData: appData)
            } else if selection == "Planning" {
                PlanningView(appData: appData)
            } else if let courseName = selection, appData.courses.keys.contains(courseName) {
                CourseDetailView(appData: appData, courseName: courseName, selection: $selection)
            } else {
                Text("Sélectionne un élément dans le menu")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $isShowingAddCourse) {
            AddCourseSheet(appData: appData, isPresented: $isShowingAddCourse)
        }
    }
}

// MARK: - FENÊTRE MODALE D'AJOUT DE COURS
struct AddCourseSheet: View {
    @ObservedObject var appData: AppData
    @Binding var isPresented: Bool
    
    @State private var newCourseName = ""
    @State private var newCourseCategory = "Général"
    @State private var newCourseColor = Color.green
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Ajouter un nouveau cours").font(.headline)
            
            TextField("Acronyme (ex: LINFO2365)", text: $newCourseName)
                .textFieldStyle(.roundedBorder)
            
            TextField("Catégorie (ex: Tronc commun)", text: $newCourseCategory)
                .textFieldStyle(.roundedBorder)
            
            ColorPicker("Couleur du cours", selection: $newCourseColor)
            
            HStack {
                Button("Annuler") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ajouter") {
                    if !newCourseName.isEmpty && appData.courses[newCourseName] == nil {
                        let newC = Course(colorHex: newCourseColor.toHex(), tasks: [], grading: [], todos: [], passingGrade: 10.0, fullName: "", professor: "", examStartTime: "08:30", examEndTime: "10:30", examLocation: "", category: newCourseCategory)
                        appData.courses[newCourseName] = newC
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCourseName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - UI COMPONENTS
struct CustomProgressBar: View {
    var progress: Double
    var color: Color
    var isMain: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: isMain ? 24 : 14)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(width: max(0, min(geometry.size.width * CGFloat(progress), geometry.size.width)), height: isMain ? 24 : 14)
                        .animation(.spring(), value: progress)
                }
            }
            .frame(height: isMain ? 24 : 14)
            
            Text("\(String(format: "%.2f", progress * 100)) % accompli")
                .font(isMain ? .body : .caption)
                .fontWeight(isMain ? .bold : .regular)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - GENERAL VIEW
struct GeneralView: View {
    @ObservedObject var appData: AppData
    
    struct BarData: Identifiable {
        let id = UUID()
        let course: String
        let type: String
        let points: Double
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("📚 Bloc.us - Ton partenaire de blocus")
                    .font(.largeTitle)
                    .bold()
                
                // FOCUS DU JOUR
                VStack(alignment: .leading, spacing: 10) {
                    Text("🎯 Focus du jour").font(.title2).bold()
                    let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
                    let todaysEvents = appData.schedule[todayStr] ?? []
                    
                    if todaysEvents.isEmpty {
                        Text("🎉 Rien de prévu au calendrier aujourd'hui. Profite de ton temps libre pour te ressourcer !")
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        ForEach(todaysEvents) { ev in
                            if let courseData = appData.courses[ev.course] {
                                VStack(alignment: .leading, spacing: 8) {
                                    if ev.type == "Examen" {
                                        Text("🚨 EXAMEN AUJOURD'HUI : \(ev.course)")
                                            .font(.headline).foregroundColor(.red)
                                        Text("🕒 Heure : \(courseData.examStartTime) - \(courseData.examEndTime)  |  📍 Lieu : \(courseData.examLocation.isEmpty ? "Non défini" : courseData.examLocation)")
                                        if !ev.description.isEmpty { Text("📝 Détails : \(ev.description)") }
                                    } else {
                                        Text("📚 \(ev.course)")
                                            .font(.headline)
                                        if !ev.description.isEmpty { Text("🎯 Objectif : \(ev.description)") }
                                        CustomProgressBar(progress: appData.computeProgress(for: ev.course), color: Color(hex: courseData.colorHex), isMain: true)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(ev.type == "Examen" ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ev.type == "Examen" ? Color.red : Color.blue, lineWidth: 1))
                            }
                        }
                    }
                    
                    // TODOs DU JOUR
                    let todaysTodos = appData.getTodaysTodos()
                    if !todaysTodos.isEmpty {
                        Text("📝 À faire aujourd'hui").font(.headline).foregroundColor(.orange).padding(.top, 10)
                        ForEach(todaysTodos, id: \.todo.id) { item in
                            HStack {
                                Button(action: {
                                    appData.courses[item.courseName]?.todos?[item.todoIndex].isDone = true
                                    appData.save()
                                }) {
                                    Image(systemName: "circle").font(.title3)
                                }.buttonStyle(.plain).foregroundColor(.orange)
                                
                                Text(item.todo.text).font(.body)
                                Text("(\(item.courseName))").font(.caption).foregroundColor(Color(hex: item.colorHex))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                
                Divider()
                Text("Vue d'ensemble de ton blocus").font(.title2).bold()
                
                if appData.courses.isEmpty {
                    Text("Ajoute des cours dans le menu de gauche pour commencer !")
                        .foregroundColor(.secondary)
                } else {
                    // GRAPHIQUES
                    HStack(alignment: .top, spacing: 20) {
                        VStack {
                            Text("Équilibre d'étude par cours").font(.headline)
                            Chart {
                                ForEach(appData.courses.keys.sorted(), id: \.self) { c in
                                    BarMark(
                                        x: .value("Progression", appData.computeProgress(for: c) * 100),
                                        y: .value("Cours", c)
                                    )
                                    .foregroundStyle(Color(hex: appData.courses[c]!.colorHex))
                                }
                            }
                            .chartXScale(domain: 0...100)
                            .frame(height: 250)
                        }
                        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        
                        VStack {
                            Text("Répartition du temps alloué par cours").font(.headline)
                            if #available(macOS 14.0, *) {
                                Chart {
                                    ForEach(appData.courses.keys.sorted(), id: \.self) { c in
                                        let days = appData.computeStudyDays(for: c).total
                                        if days > 0 {
                                            SectorMark(
                                                angle: .value("Jours", days),
                                                innerRadius: .ratio(0.5),
                                                angularInset: 1.5
                                            )
                                            .foregroundStyle(Color(hex: appData.courses[c]!.colorHex))
                                            .annotation(position: .overlay) {
                                                Text("\(days)j").font(.caption).bold().foregroundColor(.white)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 250)
                            } else {
                                Text("Nécessite macOS 14+ pour le graphique circulaire")
                            }
                        }
                        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                    }
                    
                    // Stacked Bar Points
                    VStack {
                        Text("🎯 Stratégie des points (sur 20)").font(.headline)
                        Chart {
                            ForEach(generateBarData()) { item in
                                BarMark(
                                    x: .value("Cours", item.course),
                                    y: .value("Points", item.points)
                                )
                                .foregroundStyle(by: .value("Type", item.type))
                            }
                        }
                        .chartForegroundStyleScale([
                            "1. Acquis": Color.green,
                            "2. À réussir": Color.orange,
                            "3. Bonus": Color.gray.opacity(0.3)
                        ])
                        .chartYScale(domain: 0...20)
                        .frame(height: 250)
                    }
                    .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                    
                    // Résumé textuel
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(appData.courses.keys.sorted(), id: \.self) { c in
                            let stats = appData.computeStudyDays(for: c)
                            VStack(alignment: .leading) {
                                Text(c).font(.headline)
                                Text("⏱️ Prévus : \(stats.total) j | ⏳ Restants : \(stats.remaining) j")
                                    .font(.subheadline).foregroundColor(.secondary)
                                CustomProgressBar(progress: appData.computeProgress(for: c), color: Color(hex: appData.courses[c]!.colorHex), isMain: true)
                            }
                            .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    func generateBarData() -> [BarData] {
        var result: [BarData] = []
        for (cName, data) in appData.courses {
            let target = data.passingGrade
            let earned = data.grading.reduce(0) { $0 + $1.score }
            let totGraded = data.grading.reduce(0) { $0 + $1.total }
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

// MARK: - PLANNING VIEW
struct PlanningView: View {
    @ObservedObject var appData: AppData
    
    @State private var selectedDate = Date()
    @State private var selectedType = "Étude"
    @State private var selectedCourse = ""
    @State private var eventDesc = ""
    
    let types = ["Étude", "Examen"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Programme d'étude").font(.largeTitle).bold()
                    Spacer()
                    Button("🗑️ Vider TOUT le calendrier") {
                        appData.schedule.removeAll()
                    }.buttonStyle(.bordered)
                }
                
                GroupBox("➕ Planifier une session") {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            Text("Date")
                            DatePicker("", selection: $selectedDate, displayedComponents: .date).labelsHidden()
                        }
                        VStack(alignment: .leading) {
                            Text("Type")
                            Picker("", selection: $selectedType) {
                                ForEach(types, id: \.self) { Text($0) }
                            }.labelsHidden()
                        }
                        VStack(alignment: .leading) {
                            Text("Cours")
                            Picker("", selection: $selectedCourse) {
                                Text("Sélectionner").tag("")
                                ForEach(appData.courses.keys.sorted(), id: \.self) { Text($0).tag($0) }
                            }.labelsHidden()
                        }
                        VStack(alignment: .leading) {
                            Text("Description (Optionnel)")
                            TextField("Ex: Chapitre 5", text: $eventDesc)
                        }
                        Button("Ajouter") {
                            if !selectedCourse.isEmpty {
                                appData.addScheduleEvent(date: selectedDate, type: selectedType, course: selectedCourse, description: eventDesc)
                                eventDesc = ""
                            }
                        }.buttonStyle(.borderedProminent).disabled(selectedCourse.isEmpty)
                    }
                    .padding(5)
                }
                
                Divider()
                
                let today = Date()
                let calendar = Calendar.current
                let currentMonth = calendar.component(.month, from: today)
                let currentYear = calendar.component(.year, from: today)
                
                let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: today)!
                let nextMonth = calendar.component(.month, from: nextMonthDate)
                let nextYear = calendar.component(.year, from: nextMonthDate)
                
                MonthCalendarView(appData: appData, year: currentYear, month: currentMonth)
                MonthCalendarView(appData: appData, year: nextYear, month: nextMonth)
            }
            .padding()
        }
    }
}

// MARK: - MONTH CALENDAR HELPER
struct MonthCalendarView: View {
    @ObservedObject var appData: AppData
    let year: Int
    let month: Int
    
    let daysOfWeek = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(monthName(month)) \(String(year))")
                .font(.title2).bold().padding(.top)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(daysOfWeek, id: \.self) { d in
                    Text(d).bold().frame(maxWidth: .infinity, alignment: .center)
                }
                
                let days = getDaysArray()
                ForEach(0..<days.count, id: \.self) { i in
                    if let dayNum = days[i] {
                        let dateStr = String(format: "%04d-%02d-%02d", year, month, dayNum)
                        CalendarCell(appData: appData, dayNum: dayNum, dateStr: dateStr)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
        }
    }
    
    func getDaysArray() -> [Int?] {
        var days: [Int?] = []
        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstOfMonth = Calendar.current.date(from: components) else { return [] }
        
        let range = Calendar.current.range(of: .day, in: .month, for: firstOfMonth)!
        let numDays = range.count
        
        var firstWeekday = Calendar.current.component(.weekday, from: firstOfMonth)
        firstWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1
        
        for _ in 1..<firstWeekday { days.append(nil) }
        for d in 1...numDays { days.append(d) }
        return days
    }
    
    func monthName(_ m: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.monthSymbols[m - 1].capitalized
    }
}

struct CalendarCell: View {
    @ObservedObject var appData: AppData
    let dayNum: Int
    let dateStr: String
    
    var body: some View {
        let isToday = dateStr == DateFormatter.yyyyMMdd.string(from: Date())
        
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(dayNum)")
                .bold()
                .foregroundColor(isToday ? .white : .primary)
                .padding(6)
                .background(isToday ? Color.red : Color.clear)
                .clipShape(Circle())
                .padding([.top, .trailing], 5)
            
            if let events = appData.schedule[dateStr] {
                ForEach(events) { ev in
                    let colorHex = appData.courses[ev.course]?.colorHex ?? "#4CAF50"
                    let isExam = ev.type == "Examen"
                    
                    HStack {
                        Text(isExam ? "🚨 EXAM: \(ev.course)" : "📚 \(ev.course)")
                            .font(.system(size: 10, weight: isExam ? .heavy : .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: { appData.removeScheduleEvent(dateStr: dateStr, eventId: ev.id) }) {
                            Image(systemName: "trash").font(.system(size: 9))
                        }.buttonStyle(.plain)
                    }
                    .padding(4)
                    .background(Color(hex: colorHex).opacity(0.3))
                    .overlay(Rectangle().frame(width: 4).foregroundColor(Color(hex: colorHex)), alignment: .leading)
                    .cornerRadius(4)
                    .padding(.horizontal, 2)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topTrailing)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isToday ? Color.red.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: isToday ? 2 : 1))
    }
}

// MARK: - COURSE DETAIL VIEW
struct CourseDetailView: View {
    @ObservedObject var appData: AppData
    let courseName: String
    @Binding var selection: String?
    
    @State private var newTaskName = ""
    @State private var newTaskTotal: Double = 1.0
    
    @State private var newGradeName = ""
    @State private var newGradeTotal: Double = 20.0
    @State private var newGradeScore: Double = 0.0
    
    @State private var editedAcronym = ""
    
    @State private var newTodoText = ""
    @State private var newTodoHasDate = false
    @State private var newTodoDate = Date()
    
    var body: some View {
        if let course = appData.courses[courseName] {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(courseName).font(.largeTitle).bold()
                            if !course.fullName.isEmpty { Text(course.fullName).font(.title3) }
                            if !course.professor.isEmpty { Text("Professeur : \(course.professor)").italic() }
                        }
                        Spacer()
                        Button("❌ Supprimer le cours", role: .destructive) {
                            appData.courses.removeValue(forKey: courseName)
                            selection = "Général"
                        }.buttonStyle(.bordered)
                    }
                    
                    CustomProgressBar(progress: appData.computeProgress(for: courseName), color: Color(hex: course.colorHex), isMain: true)
                    
                    DisclosureGroup("⚙️ Paramètres du cours") {
                        VStack(alignment: .leading, spacing: 15) {
                            
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading) {
                                    Text("Acronyme (Nom du cours)")
                                    TextField("Ex: LINFO", text: $editedAcronym)
                                        .textFieldStyle(.roundedBorder)
                                }
                                if editedAcronym != courseName && !editedAcronym.isEmpty {
                                    Button("Renommer") {
                                        appData.renameCourse(oldName: courseName, newName: editedAcronym)
                                        selection = editedAcronym
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Nom complet")
                                    TextField("Ex: Algorithmique", text: binding(for: \.fullName))
                                }
                                VStack(alignment: .leading) {
                                    Text("Professeur")
                                    TextField("Ex: John Doe", text: binding(for: \.professor))
                                }
                            }
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Catégorie (Section)")
                                    TextField("Ex: Tronc commun", text: Binding(
                                        get: { course.category ?? "Général" },
                                        set: { appData.courses[courseName]?.category = $0.isEmpty ? nil : $0 }
                                    ))
                                }
                                VStack(alignment: .leading) {
                                    Text("Couleur")
                                    ColorPicker("", selection: Binding(get: { Color(hex: course.colorHex) }, set: { appData.courses[courseName]?.colorHex = $0.toHex() })).labelsHidden()
                                }
                                VStack(alignment: .leading) {
                                    Text("Cote cible (/20)")
                                    TextField("", value: binding(for: \.passingGrade), format: .number).frame(width: 60)
                                }
                            }
                            
                            Text("Informations sur l'examen").bold()
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Début (HH:MM)")
                                    TextField("", text: binding(for: \.examStartTime)).frame(width: 80)
                                }
                                VStack(alignment: .leading) {
                                    Text("Fin (HH:MM)")
                                    TextField("", text: binding(for: \.examEndTime)).frame(width: 80)
                                }
                                VStack(alignment: .leading) {
                                    Text("Lieu")
                                    TextField("", text: binding(for: \.examLocation))
                                }
                            }
                        }
                        .padding().background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
                    }
                    .onAppear { editedAcronym = courseName }
                    .onChange(of: courseName) { newValue in editedAcronym = newValue }
                    
                    Divider()
                    
                    Text("Tâches").font(.title2).bold()
                    HStack {
                        TextField("Nom (ex: Chapitre 1)", text: $newTaskName)
                        Text("Total :")
                        TextField("", value: $newTaskTotal, format: .number).frame(width: 50)
                        Button("Ajouter") {
                            if !newTaskName.isEmpty {
                                appData.courses[courseName]?.tasks.append(TaskItem(name: newTaskName, total: newTaskTotal, done: 0))
                                newTaskName = ""
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                    
                    ForEach(Array(course.tasks.enumerated()), id: \.element.id) { index, task in
                        VStack(alignment: .leading) {
                            Text(task.name).font(.headline)
                            CustomProgressBar(progress: task.total > 0 ? task.done / task.total : 0, color: Color(hex: course.colorHex), isMain: false)
                            HStack {
                                Text("\(String(format: "%.2f", task.done)) / \(String(format: "%.2f", task.total))")
                                Spacer()
                                Button("➖") {
                                    if task.done > 0 { appData.courses[courseName]?.tasks[index].done -= 1 }
                                }
                                Button("➕") {
                                    if task.done < task.total { appData.courses[courseName]?.tasks[index].done += 1 }
                                }
                                Button("❌") {
                                    appData.courses[courseName]?.tasks.remove(at: index)
                                }.foregroundColor(.red)
                            }
                        }.padding(.bottom, 10)
                    }
                    
                    Divider()
                    
                    Text("🗓️ Planification").font(.title2).bold()
                    let stats = appData.computeStudyDays(for: courseName)
                    Text("⏱️ Total prévu : \(stats.total) jour(s)  |  ⏳ Reste à faire : \(stats.remaining) jour(s)")
                    
                    let plannedDates = getPlannedDates(for: courseName)
                    if plannedDates.isEmpty {
                        Text("- Aucun jour planifié dans le calendrier pour l'instant.")
                    } else {
                        ForEach(plannedDates, id: \.dateStr) { item in
                            Text(item.isExam ? "- 🚨 **\(item.formatted)** (Examen)\(item.desc)" : "- 📚 \(item.formatted)\(item.desc)")
                        }
                    }
                    
                    Divider()
                    
                    Text("🎓 Cotation").font(.title2).bold()
                    HStack {
                        TextField("Nom (ex: TP1)", text: $newGradeName)
                        Text("Score :")
                        TextField("", value: $newGradeScore, format: .number).frame(width: 50)
                        Text("Sur :")
                        TextField("", value: $newGradeTotal, format: .number).frame(width: 50)
                        Button("Ajouter") {
                            if !newGradeName.isEmpty {
                                appData.courses[courseName]?.grading.append(GradingItem(name: newGradeName, total: newGradeTotal, score: newGradeScore))
                                newGradeName = ""
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                    
                    ForEach(Array(course.grading.enumerated()), id: \.element.id) { index, grade in
                        HStack {
                            Text("**\(grade.name)**")
                                .frame(width: 150, alignment: .leading)
                            
                            TextField("Score", value: Binding(
                                get: { grade.score },
                                set: { appData.courses[courseName]?.grading[index].score = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            
                            Text("/ \(String(format: "%.2f", grade.total)) pts")
                                .frame(width: 80, alignment: .leading)
                            
                            Text("\(String(format: "%.2f", (grade.total > 0 ? (grade.score / grade.total) : 0) * 100)) %")
                                .frame(width: 80, alignment: .trailing)
                            
                            Spacer()
                            Button("❌") {
                                appData.courses[courseName]?.grading.remove(at: index)
                            }.foregroundColor(.red)
                        }.padding(.vertical, 4)
                    }
                    
                    Divider()
                    let (examTotal, needed) = computeExamTarget(grading: course.grading, target: course.passingGrade)
                    Text("🧪 Examen (Cible: \(String(format: "%.2f", course.passingGrade))/20)").font(.title2).bold()
                    Text("Examen sur **\(String(format: "%.2f", examTotal)) points**")
                    if examTotal > 0 {
                        let percentage = (needed / examTotal) * 100
                        Text("🎯 Tu dois avoir **\(String(format: "%.2f", needed)) / \(String(format: "%.2f", examTotal))** pour atteindre ton objectif (\(String(format: "%.1f", percentage))%)")
                    } else {
                        Text("🎉 Objectif déjà atteint ou dépassé avec la cotation continue !")
                            .foregroundColor(.green).bold()
                    }
                    
                    Divider()
                    
                    // SECTION TODOs
                    Text("📝 À faire (TODO)").font(.title2).bold()
                    HStack {
                        TextField("Nouvelle tâche (ex: Imprimer syllabus)...", text: $newTodoText)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Avec date", isOn: $newTodoHasDate)
                        if newTodoHasDate {
                            DatePicker("", selection: $newTodoDate)
                                .labelsHidden()
                        }
                        Button("Ajouter") {
                            if !newTodoText.isEmpty {
                                var currentTodos = appData.courses[courseName]?.todos ?? []
                                currentTodos.append(TodoItem(text: newTodoText, dueDate: newTodoHasDate ? newTodoDate : nil))
                                appData.courses[courseName]?.todos = currentTodos
                                newTodoText = ""
                                newTodoHasDate = false
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                    
                    let todos = course.todos ?? []
                    if todos.isEmpty {
                        Text("Aucune tâche en attente.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 5)
                    } else {
                        ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                            HStack {
                                Button(action: {
                                    appData.courses[courseName]?.todos?[index].isDone.toggle()
                                }) {
                                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(todo.isDone ? .green : .gray)
                                        .font(.title3)
                                }.buttonStyle(.plain)
                                
                                TextField("Tâche", text: Binding(
                                    get: { todo.text },
                                    set: { appData.courses[courseName]?.todos?[index].text = $0 }
                                ))
                                .strikethrough(todo.isDone)
                                .foregroundColor(todo.isDone ? .secondary : .primary)
                                
                                if todo.dueDate != nil {
                                    DatePicker("", selection: Binding(
                                        get: { todo.dueDate ?? Date() },
                                        set: { appData.courses[courseName]?.todos?[index].dueDate = $0 }
                                    ))
                                    .labelsHidden()
                                } else {
                                    Button(action: {
                                        appData.courses[courseName]?.todos?[index].dueDate = Date()
                                    }) {
                                        Image(systemName: "calendar.badge.plus")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Ajouter une date")
                                }
                                
                                Spacer()
                                
                                Button("❌") {
                                    appData.courses[courseName]?.todos?.remove(at: index)
                                }.foregroundColor(.red)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    func binding<T>(for keyPath: WritableKeyPath<Course, T>) -> Binding<T> {
        Binding(
            get: { appData.courses[courseName]![keyPath: keyPath] },
            set: { appData.courses[courseName]?[keyPath: keyPath] = $0 }
        )
    }
    
    func getPlannedDates(for course: String) -> [(dateStr: String, formatted: String, isExam: Bool, desc: String)] {
        var results: [(String, String, Bool, String)] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM yyyy"
        
        for (dateStr, events) in appData.schedule {
            for ev in events where ev.course == course {
                if let d = DateFormatter.yyyyMMdd.date(from: dateStr) {
                    let descText = ev.description.isEmpty ? "" : " *(Objectif: \(ev.description))*"
                    results.append((dateStr, formatter.string(from: d), ev.type == "Examen", descText))
                }
            }
        }
        return results.sorted(by: { $0.0 < $1.0 })
    }
    
    func computeExamTarget(grading: [GradingItem], target: Double) -> (Double, Double) {
        let totalPoints = grading.reduce(0) { $0 + $1.total }
        let earnedPoints = grading.reduce(0) { $0 + $1.score }
        let examTotal = max(0, 20 - totalPoints)
        let neededExam = target - earnedPoints
        return (examTotal, max(0, neededExam))
    }
}

// MARK: - MENU BAR VIEW (Fenêtre du haut)
struct MenuBarView: View {
    @ObservedObject var appData: AppData
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("🎯 Focus du jour")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
                let todaysEvents = appData.schedule[todayStr] ?? []
                
                if todaysEvents.isEmpty {
                    Text("Rien de prévu aujourd'hui ! Profite de ton repos.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(todaysEvents) { ev in
                        if let course = appData.courses[ev.course] {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("📚 **\(ev.course)**")
                                    Spacer()
                                    if let dayInfo = appData.currentStudyDayInfo(for: ev.course) {
                                        Text("Jour \(dayInfo.current)/\(dayInfo.total)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: course.colorHex).opacity(0.2))
                                            .foregroundColor(Color(hex: course.colorHex))
                                            .cornerRadius(4)
                                    }
                                }
                                
                                if !ev.description.isEmpty {
                                    Text("👉 \(ev.description)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                CustomProgressBar(progress: appData.computeProgress(for: ev.course), color: Color(hex: course.colorHex), isMain: false)
                                
                                let totalPoints = course.grading.reduce(0) { $0 + $1.total }
                                let earnedPoints = course.grading.reduce(0) { $0 + $1.score }
                                let examTotal = max(0, 20 - totalPoints)
                                let neededExam = max(0, course.passingGrade - earnedPoints)
                                
                                if examTotal > 0 {
                                    let percentage = (neededExam / examTotal) * 100
                                    Text("Objectif examen : **\(String(format: "%.2f", neededExam)) / \(String(format: "%.2f", examTotal))** (\(String(format: "%.1f", percentage))%)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("🎉 Cours déjà validé !")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                
                // TODOs DU JOUR DANS LE WIDGET
                let todaysTodos = appData.getTodaysTodos()
                if !todaysTodos.isEmpty {
                    Divider()
                    Text("📝 À faire aujourd'hui").font(.headline).foregroundColor(.orange)
                    ForEach(todaysTodos, id: \.todo.id) { item in
                        HStack {
                            Button(action: {
                                appData.courses[item.courseName]?.todos?[item.todoIndex].isDone = true
                                appData.save()
                            }) {
                                Image(systemName: "circle")
                            }.buttonStyle(.plain)
                            
                            VStack(alignment: .leading) {
                                Text(item.todo.text).font(.subheadline)
                                Text(item.courseName).font(.caption2).foregroundColor(Color(hex: item.colorHex))
                            }
                        }
                    }
                }
                
                // SOUS-SECTIONS DE TOUS LES COURS
                Divider()
                Text("📚 Progression par section").font(.headline).padding(.top, 5)
                let grouped = Dictionary(grouping: appData.courses.keys, by: { appData.courses[$0]?.category ?? "Général" })
                ForEach(grouped.keys.sorted(), id: \.self) { cat in
                    Text(cat).font(.caption).foregroundColor(.secondary).padding(.top, 5)
                    ForEach(grouped[cat]!.sorted(), id: \.self) { cName in
                        let course = appData.courses[cName]!
                        HStack {
                            Text(cName).font(.subheadline)
                            Spacer()
                            Text("\(String(format: "%.2f", appData.computeProgress(for: cName) * 100)) %")
                                .font(.caption2)
                        }
                        CustomProgressBar(progress: appData.computeProgress(for: cName), color: Color(hex: course.colorHex), isMain: false)
                    }
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    Button("Quitter Bloc.us") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 330, height: 480)
    }
}
