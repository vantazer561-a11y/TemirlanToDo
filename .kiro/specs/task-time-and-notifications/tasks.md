# Implementation Plan

## Overview

План реализован для итеративной сборки фичи `task-time-and-notifications` поверх существующего проекта `TemirlanToDo` (Swift 5, SwiftUI, iOS 15+). Каждая задача — атомарный шаг, которые в сумме дают: (1) поле `dueHasTime` на `TaskItem` с обратной совместимостью, (2) UI редактирования времени, (3) AI-ассистента с поддержкой `yyyy-MM-dd'T'HH:mm`, (4) виджет с ближайшей timed-задачей, (5) локальные уведомления через `NotificationScheduler`, (6) экран `NotificationSettingsView`.

Property-тесты реализуются через собственный helper `PBT.forAll` (XCTest, без внешних зависимостей) и каждое property ссылается на номер из секции **Correctness Properties** в `design.md`. Каждая задача и подзадача ссылается на конкретные пункты Acceptance Criteria из `requirements.md`.

Локального Xcode нет — сборка идёт через GitHub Actions (`.github/workflows/ios-build.yml`, `xcodebuild test`). Поэтому добавление файлов в проект делается ручным редактированием `TemirlanToDo.xcodeproj/project.pbxproj` (выделено в отдельную задачу 17), а финальная проверка — через push на ветку и наблюдение за CI (задача 18).

## Tasks

- [ ] 1. PBT helper и генераторы для тестов

  - [ ] 1.1 Создать `PBT.swift` с helper `forAll` и SeededRandom
    - Файл: `TemirlanToDoTests/PBT.swift`
    - `enum PBT { static let defaultIterations = 100; static func forAll<A>(_ gen: (inout SystemRandomNumberGenerator) -> A, iterations: Int = defaultIterations, file: StaticString = #file, line: UInt = #line, _ check: (A) throws -> Void) }`.
    - При падении — `XCTFail` с номером итерации и serialized входом.
    - Поддержать deterministic seed через env-переменную `PBT_SEED` (для воспроизводимости в CI).
    - _Requirements: инфраструктура для всех Property-тестов_

  - [ ] 1.2 Создать `Generators.swift` с базовыми генераторами
    - Файл: `TemirlanToDoTests/Generators.swift`
    - Генераторы: `genUUID`, `genDate(in: Date...Date)`, `genString(maxLen:)`, `genBool`, `genInt(in:)`, `genTaskItem` (с инвариантом `dueDate == nil ⇒ dueHasTime == false` и нулевыми секундами/наносекундами), `genTaskItems(count:)`, `genNotificationSettings`, `genTodayWidgetSnapshot`, `genISODateString`, `genISODateTimeString`, `genInvalidDueDateString`.
    - Все принимают `inout SystemRandomNumberGenerator` для детерминированности.
    - _Requirements: инфраструктура для Property 1-23_

- [ ] 2. Расширение `TaskItem` полем `dueHasTime` с миграцией

  - [ ] 2.1 Добавить поле `dueHasTime: Bool` в `TaskItem`
    - Файл: `TemirlanToDo/Models/TaskItem.swift`
    - Новое свойство `public var dueHasTime: Bool` после `dueDate`.
    - Параметр в `init(...)` после `dueDate: Date? = nil` со значением `dueHasTime: Bool = false` и нормализацией `self.dueHasTime = (dueDate == nil) ? false : dueHasTime`.
    - Добавить ключ `dueHasTime` в `enum CodingKeys`.
    - _Requirements: 1.1, 1.5_

  - [ ] 2.2 Реализовать кастомный `init(from decoder:)` с обратной совместимостью
    - Файл: `TemirlanToDo/Models/TaskItem.swift`
    - `decodeIfPresent` для всех опциональных и потенциально отсутствующих полей.
    - Если ключ `dueHasTime` отсутствует → значение `false`.
    - Если декодированный `dueDate == nil` → принудительно `dueHasTime = false`.
    - `notes`, `isCompleted`, `isImportant`, `isInMyDay` остаются с прежней семантикой через `decodeIfPresent`.
    - _Requirements: 1.3, 1.4, 10.1_

  - [ ] 2.3 Property-тест: JSON round-trip TaskItem
    - Файл: `TemirlanToDoTests/TaskItemMigrationTests.swift` (новый)
    - **Property 1: TaskItem JSON round-trip**
    - **Validates: Requirements 1.2, 10.4**
    - Использует `genTaskItem` из задачи 1.2.
    - _Requirements: 1.2, 10.4_

  - [ ] 2.4 Property-тест: декодирование JSON без ключа `dueHasTime`
    - Файл: `TemirlanToDoTests/TaskItemMigrationTests.swift`
    - **Property 2: Backward-compatible decode без `dueHasTime`**
    - **Validates: Requirements 1.3, 10.1**
    - Сериализуем задачу, удаляем ключ `dueHasTime` из JSON-словаря, декодируем — должно вернуть `dueHasTime == false` и остальные поля без изменений.
    - _Requirements: 1.3, 10.1_

  - [ ] 2.5 Property-тест: инвариант `dueDate == nil ⇒ dueHasTime == false`
    - Файл: `TemirlanToDoTests/TaskItemMigrationTests.swift`
    - **Property 3: Инвариант nil-due**
    - **Validates: Requirements 1.4, 1.5, 1.8**
    - Генерируем `TaskItem` со случайными `dueDate (nil/non-nil)` и `dueHasTime (Bool.random())`. Проверяем, что после `init` инвариант держится. Дополнительно: после `decode` JSON с `dueDate=null, dueHasTime=true` итог — `dueHasTime == false`.
    - _Requirements: 1.4, 1.5, 1.8_

  - [ ] 2.6 Property-тест: каждая закодированная задача содержит ключ `dueHasTime`
    - Файл: `TemirlanToDoTests/TaskItemMigrationTests.swift`
    - **Property 22: каждая закодированная задача содержит ключ `dueHasTime`**
    - **Validates: Requirements 10.3**
    - Для случайного `[TaskItem]` число вхождений `"dueHasTime"` в JSON равно `tasks.count`.
    - _Requirements: 10.3_

- [ ] 3. Методы управления временем в `TaskStore`

  - [ ] 3.1 Добавить метод `setDueDate(_:for:)` в `TaskStore`
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Сигнатура: `public func setDueDate(_ date: Date, for id: TaskItem.ID, calendar: Calendar = .current)`.
    - Нормализует `date` к `calendar.startOfDay(for: date)`, ставит `dueHasTime = false`, обновляет `updatedAt`, вызывает `save()`.
    - _Requirements: 1.5, 2.3_

  - [ ] 3.2 Добавить метод `setDueTime(hour:minute:for:)` в `TaskStore`
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Сигнатура: `public func setDueTime(hour: Int, minute: Int, for id: TaskItem.ID, calendar: Calendar = .current)`.
    - Если `tasks[index].dueDate == nil` → no-op (инвариант 1.5).
    - Иначе: `Calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate)`, обнуляет наносекунды, ставит `dueHasTime = true`, обновляет `updatedAt`, вызывает `save()`.
    - _Requirements: 1.5, 1.6_

  - [ ] 3.3 Добавить метод `clearDueTime(for:)` в `TaskStore`
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Сигнатура: `public func clearDueTime(for id: TaskItem.ID, calendar: Calendar = .current)`.
    - Если `dueDate != nil`: нормализует к `calendar.startOfDay(for: dueDate)`, ставит `dueHasTime = false`, обновляет `updatedAt`, `save()`.
    - _Requirements: 1.7, 2.6_

  - [ ] 3.4 Добавить метод `clearDueDate(for:)` в `TaskStore`
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Сигнатура: `public func clearDueDate(for id: TaskItem.ID)`.
    - Ставит `dueDate = nil`, `dueHasTime = false`, обновляет `updatedAt`, `save()`.
    - _Requirements: 1.8, 2.2_

  - [ ] 3.5 Property-тест: setDueTime сохраняет компоненты времени
    - Файл: `TemirlanToDoTests/TaskStoreTimeTests.swift` (новый)
    - **Property 4: setDueDate(hour, minute) сохраняет компоненты**
    - **Validates: Requirements 1.6**
    - Для случайных `(hour ∈ 0..23, minute ∈ 0..59)` после `setDueTime` поле `dueDate` имеет ровно эти компоненты, секунды/наносекунды = 0, `dueHasTime == true`.
    - _Requirements: 1.6_

  - [ ] 3.6 Property-тест: clearDueTime нормализует к началу дня
    - Файл: `TemirlanToDoTests/TaskStoreTimeTests.swift`
    - **Property 5: clearTime нормализует к началу дня**
    - **Validates: Requirements 1.7, 2.6**
    - Для случайной задачи с `dueDate != nil` после `clearDueTime` календарная дата (year/month/day) не меняется, hour/minute/second/nanosecond == 0, `dueHasTime == false`.
    - _Requirements: 1.7, 2.6_

  - [ ] 3.7 Property-тест: TaskStore round-trip через storage
    - Файл: `TemirlanToDoTests/TaskStoreTimeTests.swift`
    - **Property 7: TaskStore-уровневый round-trip**
    - **Validates: Requirements 2.7**
    - Создать задачу через `addTask`, изменить через `updateTask` (включая `dueDate`/`dueHasTime`), пересоздать `TaskStore` с тем же `TaskStorage` (file-backed) — задача загружается с теми же значениями.
    - _Requirements: 2.7_

  - [ ] 3.8 Unit-тест: clearDueDate обнуляет оба поля и `dueHasTime` инвариант после clearDueDate
    - Файл: `TemirlanToDoTests/TaskStoreTimeTests.swift`
    - Создать задачу с `dueDate != nil, dueHasTime == true`, вызвать `clearDueDate`, проверить `dueDate == nil && dueHasTime == false`.
    - _Requirements: 1.8_

- [ ] 4. AI-ассистент: парсер двух форматов `dueDate` и семантика `dueDateProvided`

  - [ ] 4.1 Добавить `parseAssistantDueDate(_:calendar:)` в `TaskStore`
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Возвращает `(Date?, Bool, Bool)` — `(parsedDate, hasTime, isValid)`.
    - Два `DateFormatter`: `yyyy-MM-dd` и `yyyy-MM-dd'T'HH:mm`, оба с `Locale(identifier: "en_US_POSIX")`, `calendar.timeZone`.
    - Пустая/`nil` строка → `(nil, false, true)` (валидно).
    - Сначала пробуем строгий формат с временем, потом без; если не парсится — `(nil, false, false)`.
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ] 4.2 Добавить custom `init(from decoder:)` в `AssistantAction` с флагом `dueDateProvided`
    - Файл: `TemirlanToDo/AI/AssistantModels.swift`
    - Новое поле `public private(set) var dueDateProvided: Bool` (НЕ кодируется обратно — только декодирование).
    - В `init(from:)`: `dueDateProvided = container.contains(.dueDate)`, `dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)`.
    - Семантика: ключ отсутствует → не трогать. Ключ `null` → очистить. Ключ-строка → парсить.
    - Обновить регулярный init `AssistantAction.init(...)` — добавить параметр `dueDateProvided: Bool = true` (по умолчанию для programmatic use).
    - _Requirements: 4.1, 4.4_

  - [ ] 4.3 Переписать `applyAssistantActions` на новую семантику
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Для `createTask`: `parseAssistantDueDate(action.dueDate, calendar:)` → если `isValid == false` выставить `lastErrorMessage = "AI вернул некорректный формат даты"` и не записывать `dueDate`/`dueHasTime` (создать без даты); иначе записать `dueDate` и `dueHasTime` из результата.
    - Для `updateTask`:
      - `dueDateProvided == false` → не трогать `dueDate`/`dueHasTime`.
      - `dueDateProvided == true && dueDate == nil` → `dueDate = nil; dueHasTime = false`.
      - `dueDateProvided == true && dueDate != nil` → `parseAssistantDueDate`; при `isValid == false` оставить поля без изменений и выставить `lastErrorMessage`; при валидном — записать оба поля.
    - В обоих случаях — остальные поля действия (`title`, `notes`, `isImportant`, `isInMyDay`, `isCompleted`) применяются независимо от валидности `dueDate`. Цикл по `actions` не прерывается.
    - Удалить старый приватный хелпер `date(from:calendar:)` после переноса логики.
    - _Requirements: 4.2, 4.3, 4.4, 4.6_

  - [ ] 4.4 Property-тест: parseAssistantDueDate round-trip для двух форматов
    - Файл: `TemirlanToDoTests/AssistantDueDateParseTests.swift` (новый)
    - **Property 9: parseAssistantDueDate round-trip для двух форматов**
    - **Validates: Requirements 4.1, 4.2, 4.3**
    - Для случайной даты с нулевыми секундами и `hasTime: Bool`: сериализуем строкой соответствующего формата, парсим, ожидаем `(date, hasTime, true)`.
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ] 4.5 Property-тест: невалидный `dueDate` не модифицирует задачу и не прерывает батч
    - Файл: `TemirlanToDoTests/AssistantDueDateParseTests.swift`
    - **Property 10: Невалидный `dueDate` не модифицирует задачу**
    - **Validates: Requirements 4.6**
    - Генерируем батч из 3+ действий, в одном — невалидный `dueDate` (например, `"2026/05/24"`, `"hello"`, `"2026-05-24T25:00"`). Проверяем: целевая задача не изменилась по `dueDate`/`dueHasTime`; `lastErrorMessage != nil`; остальные действия батча применены (включая последующие); другие поля в ошибочном действии тоже применены.
    - _Requirements: 4.6_

  - [ ] 4.6 Unit-тест: `dueDateProvided` отделяет «не трогать» от «очистить»
    - Файл: `TemirlanToDoTests/AssistantDueDateParseTests.swift`
    - Декодируем JSON `{"type":"update_task","taskId":"...","title":"x"}` (без ключа `dueDate`) — `dueDateProvided == false`.
    - Декодируем JSON `{"type":"update_task","taskId":"...","title":"x","dueDate":null}` — `dueDateProvided == true, dueDate == nil`.
    - Применяем оба к задаче с `dueDate != nil`: первое — `dueDate` не меняется; второе — `dueDate == nil && dueHasTime == false`.
    - _Requirements: 4.4_

- [ ] 5. Синхронизация AI-схемы и промптов с двумя форматами

  - [ ] 5.1 Обновить `AssistantSchema.json` с regex pattern для двух форматов
    - Файл: `TemirlanToDo/AI/AssistantModels.swift`
    - Поле `dueDate` в схеме: тип `["string", "null"]`, `pattern: "^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2})?$"`, `description: "ISO date 'yyyy-MM-dd' or ISO date-time 'yyyy-MM-dd'T'HH:mm' (local timezone). null clears the due date."`.
    - _Requirements: 4.5_

  - [ ] 5.2 Обновить `developerPrompt` в `AssistantService`
    - Файл: `TemirlanToDo/AI/AssistantService.swift`
    - Заменить строку «Use dueDate only as yyyy-MM-dd» на: «Use dueDate as `yyyy-MM-dd` for date-only tasks, `yyyy-MM-dd'T'HH:mm` (24-hour, local timezone) for tasks with a specific time, or `null` to clear the due date».
    - _Requirements: 4.5_

  - [ ] 5.3 Синхронизировать system-prompt в `FireworksClient`
    - Файл: `TemirlanToDo/AI/FireworksClient.swift`
    - В JSON-инструкции примера заменить `"dueDate": "yyyy-MM-dd or null"` на `"dueDate": "yyyy-MM-dd OR yyyy-MM-dd'T'HH:mm OR null"`.
    - Добавить блок «Rules for dueDate» в system-prompt: «omit the key entirely to leave the date untouched; use null to clear; use one of the two ISO formats to set».
    - _Requirements: 4.5_

  - [ ] 5.4 Snapshot-тест: схема описывает оба формата и pattern
    - Файл: `TemirlanToDoTests/AssistantSchemaTests.swift` (новый)
    - Извлечь `AssistantSchema.json["properties"]["actions"]["items"]["properties"]["dueDate"]` и проверить:
      - `description` содержит подстроки `yyyy-MM-dd` и `yyyy-MM-dd'T'HH:mm`;
      - `pattern` равен `"^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2})?$"`;
      - `type` содержит `"string"` и `"null"`.
    - Проверить, что `developerPrompt` и system-prompt в `FireworksClient` содержат обе подстроки форматов.
    - _Requirements: 4.5_

- [ ] 6. Расширение `TodayWidgetSnapshot` полями ближайшей timed-задачи

  - [ ] 6.1 Добавить `nextTimedTitle` и `nextTimedDate` в App-таргет
    - Файл: `TemirlanToDo/Models/TodayWidgetSnapshot.swift`
    - Новые опциональные поля `public var nextTimedTitle: String?` и `public var nextTimedDate: Date?`.
    - Расширить `init(...)` — параметры со значениями по умолчанию `nil`.
    - `static let empty` остаётся валидным (оба поля `nil`).
    - Codable синтезируется автоматически — отсутствие ключей в JSON декодируется в `nil`.
    - _Requirements: 9.1, 9.6, 10.2_

  - [ ] 6.2 Зеркально расширить структуру в Widget-таргете
    - Файл: `TemirlanToDoWidget/TemirlanToDoWidget.swift`
    - Добавить те же два опциональных поля в локальный `struct TodayWidgetSnapshot` (виджет читает свой Codable, не зависит от App-таргета).
    - _Requirements: 9.1, 9.6, 10.2_

  - [ ] 6.3 Property-тест: snapshot title обрезается до 80 символов без многоточия
    - Файл: `TemirlanToDoTests/TodayWidgetSnapshotTests.swift` (новый)
    - **Property 17: snapshot.nextTimedTitle обрезается до 80 символов**
    - **Validates: Requirements 9.4**
    - Для случайного `title` после построения через `TaskStore` (см. задачу 7) `snapshot.nextTimedTitle!.count == min(title.count, 80)` и равен `String(title.prefix(80))`.
    - _Requirements: 9.4_

  - [ ] 6.4 Property-тест: TodayWidgetSnapshot декодируется из старого JSON без новых ключей
    - Файл: `TemirlanToDoTests/TodayWidgetSnapshotTests.swift`
    - **Property 18: TodayWidgetSnapshot декодируется из старого JSON**
    - **Validates: Requirements 9.6, 10.2**
    - Для случайного `(count, titles, updatedAt)` сериализовать как «старый» JSON (без `nextTimedTitle`/`nextTimedDate`), декодировать и убедиться, что `nextTimedTitle == nil && nextTimedDate == nil`. Тот же тест продублировать для виджет-таргетного `TodayWidgetSnapshot`.
    - _Requirements: 9.6, 10.2_

  - [ ] 6.5 Property-тест: формат строки виджета содержит title и HH:mm
    - Файл: `TemirlanToDoTests/TodayWidgetSnapshotTests.swift`
    - **Property 19: формат строки виджета содержит title и HH:mm**
    - **Validates: Requirements 9.7**
    - После реализации задачи 16 — для пары `(title, date)` локальная функция формирования строки `"Next: <title> в <HH:mm>"` содержит подстроку `title` и подстроку `HH:mm` в локальной таймзоне устройства, 24-часовой формат с ведущими нулями.
    - _Requirements: 9.7_

- [ ] 7. Вычисление Next_Timed_Task_Today и обновление `saveTodayWidgetSnapshot`

  - [ ] 7.1 Реализовать чистую функцию выбора Next_Timed_Task_Today
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - `internal static func nextTimedTaskToday(in tasks: [TaskItem], now: Date, calendar: Calendar) -> TaskItem?`.
    - Фильтр: `!isCompleted && dueHasTime && dueDate != nil && calendar.isDate(dueDate!, inSameDayAs: now) && dueDate! >= now`.
    - Сортировка: `dueDate` по возрастанию; при равенстве `dueDate` — `id.uuidString` лексикографически по возрастанию.
    - Возвращает первый элемент или `nil`.
    - _Requirements: 9.2, 9.3, 9.5_

  - [ ] 7.2 Обновить `saveTodayWidgetSnapshot` с next-timed полями
    - Файл: `TemirlanToDo/Stores/TaskStore.swift`
    - Принимать `now: Date = Date()` и `calendar: Calendar = .current` для тестируемости.
    - Вычислить `nextTimedTaskToday` через 7.1.
    - `nextTimedTitle = next.map { String($0.title.prefix(80)) }`, `nextTimedDate = next?.dueDate`.
    - Передать в `TodayWidgetSnapshot.init(...)`.
    - Проверить, что `TodayWidgetSnapshotStore.save(...)` вызывает `WidgetCenter.shared.reloadTimelines(ofKind: "TemirlanToDoWidget")` ровно один раз за вызов (это уже верно — оставить как есть).
    - _Requirements: 9.4, 9.5, 9.9_

  - [ ] 7.3 Property-тест: Next_Timed_Task_Today выбирается детерминированно
    - Файл: `TemirlanToDoTests/TaskStoreSnapshotTests.swift` (новый)
    - **Property 16: Next_Timed_Task_Today selection алгоритм**
    - **Validates: Requirements 9.2, 9.3, 9.5**
    - Для случайного `[TaskItem]` (включая случаи равных `dueDate` и пустых множеств) и случайного `now` функция возвращает элемент из правильного множества с минимальным `dueDate`, при равенстве — с лексикографически наименьшим `id.uuidString`. Перемешивание входа не меняет результат. Если множество пустое — `nil`.
    - _Requirements: 9.2, 9.3, 9.5_

  - [ ] 7.4 Property-тест: snapshot вызывает reloadTimelines ровно один раз
    - Файл: `TemirlanToDoTests/TaskStoreSnapshotTests.swift`
    - **Property 4 (адаптация): saveTodayWidgetSnapshot — единая точка обновления виджета**
    - **Validates: Requirements 9.9**
    - Заменить `TodayWidgetSnapshotStore.save` на тестовую функцию-счётчик через `userDefaults: .standard`-инжекцию (или вынести вызов `reloadTimelines` за инжекторный фасад). Проверить: один вызов `TaskStore.save()` инициирует ровно один `reloadTimelines`. Если рефакторинг фасада требует слишком много — пометить тест skip с TODO; смысл проверяется глазами на `TodayWidgetSnapshotStore.save`.
    - _Requirements: 9.9_

- [ ] 8. Форматирование даты и времени в `TaskRowView`

  - [ ] 8.1 Добавить чистую функцию `formattedDue(date:hasTime:locale:timeZone:)`
    - Файл: `TemirlanToDo/Views/TaskRowView.swift` (или вынести в `TemirlanToDo/Views/TaskDetailViewState.swift` для совместного использования из тестов).
    - Сигнатура: `func formattedDue(date: Date, hasTime: Bool, locale: Locale = .current, timeZone: TimeZone = .current) -> String`.
    - Внутри — `DateFormatter` с `dateStyle = .short`, `timeStyle = hasTime ? .short : .none`, `locale`, `timeZone`.
    - _Requirements: 3.1, 3.2, 3.4_

  - [ ] 8.2 Использовать `formattedDue` в `TaskRowView`
    - Файл: `TemirlanToDo/Views/TaskRowView.swift`
    - Заменить `dueDate.formatted(date: .abbreviated, time: .omitted)` на `formattedDue(date: dueDate, hasTime: task.dueHasTime)`.
    - Если `task.dueDate == nil` — вообще не отображать `Label` (уже так и есть, оставить).
    - Проверить, что секция `if !task.notes.isEmpty || task.dueDate != nil || task.isInMyDay` корректно ведёт себя при `dueDate == nil`.
    - _Requirements: 3.1, 3.2, 3.3, 3.5_

  - [ ] 8.3 Property-тест: formattedDue согласован с DateFormatter
    - Файл: `TemirlanToDoTests/TaskRowFormattingTests.swift` (новый)
    - **Property 8: formatDue согласован с DateFormatter**
    - **Validates: Requirements 3.1, 3.2**
    - Для случайной `Date` и `Bool hasTime` сравнить результат с прямым обращением к `DateFormatter` с теми же параметрами. Прогнать на `Locale(identifier: "ru_RU")` и `Locale(identifier: "en_US")`.
    - _Requirements: 3.1, 3.2_

- [ ] 9. `TaskDetailView`: тумблеры Due date / Add time + extracted state helper

  - [ ] 9.1 Создать `TaskDetailViewState.swift` с чистыми helper-функциями
    - Файл: `TemirlanToDo/Views/TaskDetailViewState.swift` (новый)
    - `struct TaskDetailInitialState: Equatable { var hasDueDate: Bool; var hasDueTime: Bool }`.
    - `func makeInitialDetailState(_ task: TaskItem) -> TaskDetailInitialState` — `hasDueDate = (task.dueDate != nil)`, `hasDueTime = task.dueHasTime`.
    - `func nextRoundedQuarterHour(after now: Date, base: Date?, calendar: Calendar = .current) -> Date` — возвращает строго будущий момент в локальном календаре с `minute ∈ {0,15,30,45}`, `second == 0`, `nanosecond == 0`. Если `base != nil` и `base` приходится на тот же локальный день, что `now` — взять округление от `now`; иначе сдвинуть на следующий локальный день. Если ближайший момент пересекает полночь — календарная дата увеличивается.
    - _Requirements: 2.4, 2.8, 2.9_

  - [ ] 9.2 Расширить `TaskDetailView` тумблерами Due date / Add time и DatePicker'ами
    - Файл: `TemirlanToDo/Views/TaskDetailView.swift`
    - В `init(task:)`: `_hasDueDate = State(initialValue: makeInitialDetailState(task).hasDueDate)`, `_hasDueTime = State(initialValue: makeInitialDetailState(task).hasDueTime)`.
    - В `Section("Signals")` рядом с `Toggle("Due date", isOn: $hasDueDate)` показать `Toggle("Add time", isOn: $hasDueTime).disabled(!hasDueDate)` — оба видимы всегда.
    - При `hasDueDate` показать `DatePicker("Date", ..., displayedComponents: .date)` (как есть).
    - При `hasDueDate && hasDueTime` показать `DatePicker("Time", selection: <draft.dueDate>, displayedComponents: .hourAndMinute)`.
    - `.onChange(of: hasDueDate)`: если включается и `draft.dueDate == nil` → `draft.dueDate = Calendar.current.startOfDay(for: Date()); draft.dueHasTime = false; hasDueTime = false`. Если выключается → `draft.dueDate = nil; draft.dueHasTime = false; hasDueTime = false`.
    - `.onChange(of: hasDueTime)`: если включается и `draft.dueDate != nil` → `draft.dueDate = nextRoundedQuarterHour(after: Date(), base: draft.dueDate); draft.dueHasTime = true`. Если выключается и `draft.dueDate != nil` → `draft.dueDate = Calendar.current.startOfDay(for: draft.dueDate!); draft.dueHasTime = false`.
    - В `save()`: установить `draft.dueHasTime` соответственно `hasDueTime` и `hasDueDate`; обнулить секунды/наносекунды у `draft.dueDate`, если время задано.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9_

  - [ ] 9.3 Property-тест: nextRoundedQuarterHour инварианты
    - Файл: `TemirlanToDoTests/TaskDetailViewStateTests.swift` (новый)
    - **Property 6: nextRoundedQuarterHour строго в будущем и кратен 15 минутам**
    - **Validates: Requirements 2.4**
    - Для случайного `now` и `base ∈ {nil, same-day, other-day}`: (а) результат строго больше `now`; (б) `minute ∈ {0,15,30,45}`; (в) `second == 0 && nanosecond == 0`; (г) разница `< 15 минут` (минимальный кратный 15-минут момент в будущем). Корнер-кейс: `now` = 23:50 → результат — следующий локальный день, 00:00.
    - _Requirements: 2.4_

  - [ ] 9.4 Unit-тест: makeInitialDetailState отражает задачу
    - Файл: `TemirlanToDoTests/TaskDetailViewStateTests.swift`
    - Для трёх кейсов: `(dueDate=nil, hasTime=false)`, `(dueDate=set, hasTime=false)`, `(dueDate=set, hasTime=true)` — проверить корректность `TaskDetailInitialState`.
    - _Requirements: 2.8, 2.9_

- [ ] 10. `NotificationCenterProtocol` и `FakeNotificationCenter`

  - [ ] 10.1 Создать `NotificationCenterProtocol.swift`
    - Файл: `TemirlanToDo/Notifications/NotificationCenterProtocol.swift` (новая папка `Notifications`)
    - `protocol NotificationCenterProtocol: AnyObject` с async-методами:
      - `func getNotificationSettings() async -> UNNotificationSettings`,
      - `func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool`,
      - `func add(_ request: UNNotificationRequest) async throws`,
      - `func pendingNotificationRequests() async -> [UNNotificationRequest]`,
      - `func removePendingNotificationRequests(withIdentifiers identifiers: [String])`,
      - `func removeAllPendingNotificationRequests()`.
    - `extension UNUserNotificationCenter: NotificationCenterProtocol` — мостики через `withCheckedContinuation`.
    - _Requirements: инфраструктура для 5–7_

  - [ ] 10.2 Создать `FakeNotificationCenter` для тестов
    - Файл: `TemirlanToDoTests/FakeNotificationCenter.swift` (новый)
    - In-memory pending requests (`[String: UNNotificationRequest]`), настраиваемый `authorizationStatus` (`UNAuthorizationStatus`).
    - Счётчики: `addCallCount`, `removeCallCount`, `requestAuthorizationCallCount`.
    - Опциональный `addError: Error?` для тестирования ошибок.
    - Замечание: `UNNotificationSettings` нельзя инициализировать напрямую — использовать KVC-стаб (см. публичные test-utilities) или вернуть фейковый объект через приватную обёртку, экспонированную из `NotificationScheduler` (`NotificationCenterProtocol` экспонирует `getNotificationSettings() async -> UNAuthorizationStatus` через адаптер вместо raw `UNNotificationSettings`). При имплементации задачи 10.1 использовать enum-обёртку `NotificationAuthorizationStatus` для тестируемости (подзадача 10.3).
    - _Requirements: инфраструктура тестов_

  - [ ] 10.3 Заменить `getNotificationSettings()` на типобезопасную обёртку
    - Файл: `TemirlanToDo/Notifications/NotificationCenterProtocol.swift`
    - В протокол вместо `getNotificationSettings() async -> UNNotificationSettings` положить `getAuthorizationStatus() async -> NotificationAuthorizationStatus` (новый enum, отражающий `UNAuthorizationStatus` без зависимости от `UNNotificationSettings` инициализации).
    - В `extension UNUserNotificationCenter` адаптировать: получить `UNNotificationSettings` через системный API и смапить в enum.
    - В `FakeNotificationCenter` хранить enum напрямую — никакой KVC-магии.
    - _Requirements: инфраструктура тестов_

- [ ] 11. `NotificationSettings` и `NotificationSettingsStore`

  - [ ] 11.1 Создать `NotificationSettings.swift` (модель + TimeOfDay + default + валидация)
    - Файл: `TemirlanToDo/Notifications/NotificationSettings.swift`
    - `public struct TimeOfDay: Codable, Equatable { public var hour: Int; public var minute: Int; public init(hour: Int, minute: Int) — clamps `hour` в `0..23`, `minute` в `0..59`. }`.
    - `public struct NotificationSettings: Codable, Equatable` с полями `morningDigestEnabled: Bool`, `morningTime: TimeOfDay`, `taskRemindersEnabled: Bool`, `leadTimeMinutes: Int`.
    - `public static let allowedLeadTimes: [Int] = [5, 15, 30, 60]`.
    - `public static let `default`` = (true, 08:00, true, 15).
    - `public mutating func setLeadTime(_ value: Int) -> Bool` — отклоняет вне `allowedLeadTimes`.
    - `internal static func isValid(_ s: NotificationSettings) -> Bool` — проверяет диапазоны полей.
    - _Requirements: 6.1, 7.1, 7.2, 8.10_

  - [ ] 11.2 Создать `NotificationSettingsStore.swift` (App Group UserDefaults + fallback)
    - Файл: `TemirlanToDo/Notifications/NotificationSettingsStore.swift`
    - `public final class NotificationSettingsStore: ObservableObject` с `@Published public private(set) var settings`.
    - Ключ `notification_settings`, App Group `group.com.temirlan.todo`.
    - `init(defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier), fallback: UserDefaults = .standard)` — если App Group `nil` → использовать fallback.
    - `static func load(...)` — пытается defaults, потом fallback; при `nil`/невалидном JSON/неудачной валидации (`isValid == false`) → `.default`, БЕЗ записи в UserDefaults.
    - `@discardableResult public func save(_ next: NotificationSettings) -> Bool` — сериализует, при ошибке encode → `false`, не меняет `settings`.
    - `public func update(_ transform: (inout NotificationSettings) -> Bool) -> Bool` — для частичных обновлений.
    - _Requirements: 6.1, 7.1, 8.8, 8.9, 8.10_

  - [ ] 11.3 Property-тест: setLeadTime отвергает значения вне `{5, 15, 30, 60}`
    - Файл: `TemirlanToDoTests/NotificationSettingsTests.swift` (новый)
    - **Property 20: setLeadTime отвергает значения вне `{5, 15, 30, 60}`**
    - **Validates: Requirements 7.2**
    - Для случайного `Int v`: если `v ∉ {5, 15, 30, 60}` — `setLeadTime` возвращает `false` и `leadTimeMinutes` не меняется; иначе возвращает `true` и значение применяется.
    - _Requirements: 7.2_

  - [ ] 11.4 Property-тест: store fallback на default при невалидной/отсутствующей записи
    - Файл: `TemirlanToDoTests/NotificationSettingsTests.swift`
    - **Property 21: NotificationSettingsStore.load → default при невалидной/отсутствующей записи**
    - **Validates: Requirements 8.10**
    - Для случайного содержимого UserDefaults (отсутствие записи, произвольные байты, JSON c `leadTimeMinutes ∉ allowed` или `morningTime` вне диапазонов): `load(...)` возвращает `.default`. Использовать `UserDefaults(suiteName: "test-\(UUID())")` для изоляции.
    - _Requirements: 8.10_

  - [ ] 11.5 Unit-тест: store сначала пишет в UserDefaults, потом обновляет `@Published settings`
    - Файл: `TemirlanToDoTests/NotificationSettingsTests.swift`
    - В `Combine.sink` на `$settings` проверить, что в момент эмиссии `defaults.data(forKey: ...)` уже содержит сериализованную новую структуру.
    - _Requirements: 8.8_

- [ ] 12. `NotificationScheduler`

  - [ ] 12.1 Создать скелет `NotificationScheduler` с `@MainActor`, idempotent identifiers, конструктор
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - `@MainActor public final class NotificationScheduler: ObservableObject` с `@Published public private(set) var authorizationState: NotificationAuthorizationStatus = .notDetermined`.
    - `public static let pendingRequestLimit = 64`, `morningDigestId = "morning-digest"`, `static func taskReminderId(for: UUID) -> String`.
    - `init(center: NotificationCenterProtocol = UNUserNotificationCenter.current(), calendar: Calendar = .current, now: @escaping () -> Date = Date.init)`.
    - `os_log` Logger с категорией `Notifications`.
    - _Requirements: 5.1, 6.2, 7.4_

  - [ ] 12.2 Реализовать `requestAuthorization()` и `refreshAuthorizationStatus()`
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - `requestAuthorization() async -> NotificationAuthorizationStatus`: `try? await center.requestAuthorization(options: [.alert, .sound])`, ошибки логируются; затем обновить и вернуть статус через `refreshAuthorizationStatus()`.
    - `refreshAuthorizationStatus() async -> NotificationAuthorizationStatus`: запросить enum, обновить `authorizationState`.
    - _Requirements: 5.1, 5.2, 5.3, 5.7_

  - [ ] 12.3 Реализовать чистые функции `russianTaskWord`, `morningTitle`, `morningBody`, `taskReminderBody`
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - `static func russianTaskWord(for n: Int) -> String` по правилам Req 6.4.
    - `func morningTitle(activeCount: Int) -> String` → `"Сегодня <N> <словоформа>"`.
    - `func morningBody(activeToday: [TaskItem]) -> String`: если есть Next_Timed_Task_Today (через `TaskStore.nextTimedTaskToday(in:now:calendar:)` или локальную копию helper) → `"Ближайшая: <title> в <HH:mm>"`; иначе если есть задача с `dueDate` → выбираем по правилу 6.6.а; иначе по 6.6.б.
    - `func taskReminderBody(due: Date, leadMinutes: Int) -> String` → `"Через <leadMinutes> мин в <HH:mm>"`. `HH:mm` форматтер с `Locale(identifier: "en_US_POSIX")`, `dateFormat = "HH:mm"`, `timeZone = calendar.timeZone`.
    - _Requirements: 6.4, 6.5, 6.6, 7.5_

  - [ ] 12.4 Реализовать `rescheduleMorningDigest(tasks:settings:)`
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - Сначала `removePendingNotificationRequests(withIdentifiers: [morningDigestId])`.
    - Если `!settings.morningDigestEnabled` → выход.
    - Подсчитать активные-сегодня (`!isCompleted && TaskListKind.myDay.contains($0, calendar:)` относительно `now()`).
    - Если активных == 0 → НЕ планировать (Req 6.3 — фактически запрос не создаём; альтернатива через delegate suppress, но проще не планировать).
    - Иначе создать `UNCalendarNotificationTrigger(dateMatching: {hour:morningTime.hour, minute:morningTime.minute}, repeats: true)`, body через `morningTitle`/`morningBody`, добавить запрос с `morningDigestId`.
    - _Requirements: 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [ ] 12.5 Реализовать `rescheduleTaskReminders(tasks:settings:)` с лимитом 64
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - Получить pending, найти все с префиксом `task-reminder.`, удалить.
    - Если `!settings.taskRemindersEnabled` → выход.
    - Кандидаты: `!isCompleted && dueHasTime && dueDate != nil && dueDate! − leadTime > now()`.
    - Сортировать по возрастанию `dueDate`. `reservedSlots = morningDigestEnabled ? 1 : 0`. `allowed = max(0, 64 - reservedSlots)`. `prefix(allowed)`.
    - Для каждого: `scheduleTaskReminder(for:leadTime:)` — `UNCalendarNotificationTrigger(dateMatching: components([.year,.month,.day,.hour,.minute] of fireDate), repeats: false)`, identifier `task-reminder.<UUID>`, title = `task.title`, body = `taskReminderBody`.
    - Лог `os_log` если что-то скипнули из-за лимита.
    - _Requirements: 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.13_

  - [ ] 12.6 Реализовать `synchronize(with:settings:)`, `rescheduleAll`, `cancel(for:)`, `cancelAll()`
    - Файл: `TemirlanToDo/Notifications/NotificationScheduler.swift`
    - `synchronize(with: tasks, settings:)`: `state = await refreshAuthorizationStatus()`. Если `state ∉ {.authorized, .provisional}` → `cancelAll()` (Req 5.6, 6.7, 7.12). Иначе `rescheduleAll(...)`.
    - `rescheduleAll(tasks:settings:)`: вызывает `rescheduleMorningDigest` и `rescheduleTaskReminders` последовательно.
    - `cancel(for: UUID)`: `removePendingNotificationRequests(withIdentifiers: [taskReminderId(for: id)])`.
    - `cancelAll()`: `removeAllPendingNotificationRequests()` (или явно по идентификаторам, если вдруг будут чужие).
    - _Requirements: 5.6, 5.7, 5.8, 6.7, 7.6, 7.7, 7.9, 7.10, 7.11, 7.12_

  - [ ] 12.7 Property-тест: synchronize детерминирует целевое множество pending (идемпотентность)
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift` (новый)
    - **Property 11: synchronize детерминирует целевое множество pending**
    - **Validates: Requirements 5.6, 5.8, 6.2, 6.3, 6.7, 6.8, 7.3, 7.4, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12**
    - Для случайных `[TaskItem]`, случайных `NotificationSettings`, случайного `authState`: вычислить ожидаемый target set; вызвать `synchronize`; pending == target. Повторный вызов `synchronize` не меняет состояние.
    - _Requirements: 5.6, 5.8, 6.2, 6.3, 6.7, 6.8, 7.3, 7.4, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12_

  - [ ] 12.8 Property-тест: лимит 64 pending — упорядочивание и обрезание
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift`
    - **Property 12: лимит 64 pending — упорядочивание и обрезание**
    - **Validates: Requirements 7.13**
    - Сгенерировать >100 timed-задач в будущем; после `synchronize` общее число pending ≤ 64; набор оставленных task-reminder = первые `min(N, 64 − reservedForMorning)` по `dueDate`.
    - _Requirements: 7.13_

  - [ ] 12.9 Property-тест: russianTaskWord по русским правилам
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift`
    - **Property 13: russianTaskWord по русским правилам**
    - **Validates: Requirements 6.4**
    - Для всех `n ∈ 0..1000` сравнить с reference-реализацией. Точечные кейсы: 1, 2, 5, 11, 21, 22, 25, 101, 111, 112, 121.
    - _Requirements: 6.4_

  - [ ] 12.10 Property-тест: morning body содержит правильное содержимое
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift`
    - **Property 14: morning notification body содержит правильное содержимое**
    - **Validates: Requirements 6.5, 6.6**
    - Если есть Next_Timed_Task_Today → body содержит `title` и подстроку `"в HH:mm"` для `dueDate` в локальной таймзоне. Иначе → body содержит `title` выбранной по 6.6 задачи.
    - _Requirements: 6.5, 6.6_

  - [ ] 12.11 Property-тест: task reminder body содержит leadTime и время
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift`
    - **Property 15: task reminder body содержит leadTime и время**
    - **Validates: Requirements 7.5**
    - Для случайного `dueDate` и `leadMinutes ∈ {5, 15, 30, 60}` body содержит `"Через <leadMinutes> мин"` и `"в HH:mm"`.
    - _Requirements: 7.5_

  - [ ] 12.12 Unit-тест: cancelAll и .denied → no-op
    - Файл: `TemirlanToDoTests/NotificationSchedulerTests.swift`
    - При `authorizationStatus = .denied` после `synchronize` pending пуст; `add` не вызывался (`addCallCount == 0`).
    - _Requirements: 5.6, 6.7, 7.12_

- [ ] 13. `NotificationSettingsView`

  - [ ] 13.1 Создать `NotificationSettingsView.swift`
    - Файл: `TemirlanToDo/Views/NotificationSettingsView.swift` (новый)
    - `Form` с тремя секциями: баннер `.denied` (если `scheduler.authorizationState == .denied`), Morning summary, Task reminders.
    - Баннер: текст «Разрешение на уведомления отключено» + кнопка «Открыть настройки iOS», открывающая `URL(string: UIApplication.openSettingsURLString)`.
    - Секция Morning: `Toggle("Morning summary", isOn: <binding>)`. При `morningDigestEnabled == true` — `DatePicker("Время", selection: <morningTime>, displayedComponents: .hourAndMinute)`.
    - Секция Task reminders: `Toggle("Task reminders", isOn: <binding>)`. При `taskRemindersEnabled == true` — `Picker("За сколько до", selection: <leadTime>) { ForEach(NotificationSettings.allowedLeadTimes, id: \.self) { Text("\($0) мин").tag($0) } }`.
    - Тумблеры `.disabled(scheduler.authorizationState == .denied)`.
    - При ошибке сохранения — секция с `Text(saveError).foregroundColor(.red)`.
    - `.task { if .notDetermined → await requestAuthorization(); else → await refreshAuthorizationStatus() }`.
    - _Requirements: 5.4, 5.5, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.9_

  - [ ] 13.2 Реализовать биндинги с request-on-toggle и сохранением
    - Файл: `TemirlanToDo/Views/NotificationSettingsView.swift`
    - Каждый биндинг (для каждого тумблера/picker'а): при `set`:
      1. Если `scheduler.authorizationState == .notDetermined` → `await scheduler.requestAuthorization()`. При ошибке статуса (`.denied` после запроса) — не менять `settings`, выставить `saveError`.
      2. Сформировать `next: NotificationSettings`. Если валидация (`leadTimeMinutes ∈ allowed` и т.п.) не пройдёт — `saveError`, не вызывать `save`.
      3. `let ok = settingsStore.save(next)`. Если `false` → `saveError = "Не удалось сохранить настройки"`, не дёргать `synchronize`.
      4. Если `true` → `Task { await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings) }`.
    - _Requirements: 5.2, 5.3, 8.8, 8.9_

- [ ] 14. Точка входа из `RootView`: кнопка-колокольчик в toolbar

  - [ ] 14.1 Добавить toolbar item с `bell.fill` → `NotificationSettingsView`
    - Файл: `TemirlanToDo/Views/RootView.swift`
    - Так как `.navigationBarHidden(true)` скрывает toolbar, заменить на кастомный заголовок: либо снять `navigationBarHidden`, либо в существующий header `Section { ... } header: { VStack { ... } }` добавить `HStack { Spacer(); NavigationLink(destination: NotificationSettingsView()) { Image(systemName: "bell.fill") } }`.
    - Кнопка с `accessibilityLabel("Notification settings")` и цветом `CyberpunkTheme.cyan`.
    - _Requirements: 8.1_

- [ ] 15. Интеграция в `TemirlanToDoApp`: scenePhase + проводка коллбэков

  - [ ] 15.1 Добавить `@StateObject` для scheduler и settingsStore + environmentObject
    - Файл: `TemirlanToDo/TemirlanToDoApp.swift`
    - `@StateObject private var settingsStore = NotificationSettingsStore()`.
    - `@StateObject private var scheduler = NotificationScheduler()`.
    - В `WindowGroup.body` передать `.environmentObject(scheduler)` и `.environmentObject(settingsStore)` рядом с `.environmentObject(store)`.
    - _Requirements: 6.1, 8.1_

  - [ ] 15.2 Добавить `@Environment(\.scenePhase)` и `onChange(of: scenePhase)`
    - Файл: `TemirlanToDo/TemirlanToDoApp.swift`
    - `@Environment(\.scenePhase) private var scenePhase`.
    - `.onChange(of: scenePhase) { phase in if phase == .active { Task { await scheduler.refreshAuthorizationStatus(); await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings) } } }`.
    - _Requirements: 5.7, 5.8, 7.11_

  - [ ] 15.3 Добавить `notifySchedulerNeedsSync` closure в `TaskStore` и провязать в App
    - Файл: `TemirlanToDo/Stores/TaskStore.swift` + `TemirlanToDo/TemirlanToDoApp.swift`
    - В `TaskStore`: `public var notifySchedulerNeedsSync: (() -> Void)?` и вызов `notifySchedulerNeedsSync?()` в конце `save()` после успешной записи (после `saveTodayWidgetSnapshot` и `lastErrorMessage = nil`).
    - В `TemirlanToDoApp` через `.onAppear` (на корневом view) или `.task`: `store.notifySchedulerNeedsSync = { [weak store, scheduler, settingsStore] in guard let store else { return }; Task { await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings) } }`.
    - _Requirements: 6.8, 7.6, 7.9, 7.10, 7.11_

- [ ] 16. Виджет: рендер «Next: <title> в HH:mm»

  - [ ] 16.1 Добавить блок «Next» в `TodayTasksWidgetView`
    - Файл: `TemirlanToDoWidget/TemirlanToDoWidget.swift`
    - Под существующим списком заголовков: `if let title = entry.snapshot.nextTimedTitle, let date = entry.snapshot.nextTimedDate { HStack(spacing: 6) { Image(systemName: "alarm").foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.0)); Text("Next: \(title) в \(timeFormatter.string(from: date))").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.9)).lineLimit(1) } }`.
    - Локальный `static let timeFormatter: DateFormatter` с `dateFormat = "HH:mm"`, `locale = Locale(identifier: "en_US_POSIX")`, `timeZone = .current`.
    - _Requirements: 9.7, 9.8_

  - [ ] 16.2 Обновить placeholder и `getSnapshot` примерами с next-timed
    - Файл: `TemirlanToDoWidget/TemirlanToDoWidget.swift`
    - В `placeholder(in:)` создать `TodayWidgetSnapshot(count: 3, titles: [...], updatedAt: Date(), nextTimedTitle: "Митинг с Анной", nextTimedDate: Date().addingTimeInterval(3600))` для красивого preview.
    - _Requirements: 9.1_

- [ ] 17. Обновление `TemirlanToDo.xcodeproj/project.pbxproj`

  - [ ] 17.1 Добавить новые app-таргет файлы в `project.pbxproj`
    - Файл: `TemirlanToDo.xcodeproj/project.pbxproj`
    - Создать `PBXFileReference` и `PBXBuildFile` записи для:
      - `TemirlanToDo/Notifications/NotificationCenterProtocol.swift`,
      - `TemirlanToDo/Notifications/NotificationSettings.swift`,
      - `TemirlanToDo/Notifications/NotificationSettingsStore.swift`,
      - `TemirlanToDo/Notifications/NotificationScheduler.swift`,
      - `TemirlanToDo/Views/NotificationSettingsView.swift`,
      - `TemirlanToDo/Views/TaskDetailViewState.swift`.
    - Добавить файлы в `PBXSourcesBuildPhase` для target `TemirlanToDo` (групповой ID `080000000000000000000001`).
    - Создать новую `PBXGroup` для `Notifications` (под `070000000000000000000002 /* TemirlanToDo */`) и положить туда четыре файла.
    - Положить `NotificationSettingsView.swift` и `TaskDetailViewState.swift` в существующую группу `Views` (`070000000000000000000009`).
    - Использовать неконфликтующие 24-значные hex-id (например, `02000000000000000000002X` для FileRef, `01000000000000000000002X` для BuildFile).
    - _Requirements: инфраструктура для всех новых файлов_

  - [ ] 17.2 Добавить новые тестовые файлы в `project.pbxproj`
    - Файл: `TemirlanToDo.xcodeproj/project.pbxproj`
    - Создать `PBXFileReference` и `PBXBuildFile` записи для:
      - `TemirlanToDoTests/PBT.swift`,
      - `TemirlanToDoTests/Generators.swift`,
      - `TemirlanToDoTests/FakeNotificationCenter.swift`,
      - `TemirlanToDoTests/TaskItemMigrationTests.swift`,
      - `TemirlanToDoTests/TaskStoreTimeTests.swift`,
      - `TemirlanToDoTests/AssistantDueDateParseTests.swift`,
      - `TemirlanToDoTests/AssistantSchemaTests.swift`,
      - `TemirlanToDoTests/TodayWidgetSnapshotTests.swift`,
      - `TemirlanToDoTests/TaskStoreSnapshotTests.swift`,
      - `TemirlanToDoTests/TaskRowFormattingTests.swift`,
      - `TemirlanToDoTests/TaskDetailViewStateTests.swift`,
      - `TemirlanToDoTests/NotificationSettingsTests.swift`,
      - `TemirlanToDoTests/NotificationSchedulerTests.swift`.
    - Все добавить в `PBXSourcesBuildPhase` target `TemirlanToDoTests` (`080000000000000000000003`).
    - Все добавить в существующую `PBXGroup` `TemirlanToDoTests` (`070000000000000000000007`).
    - _Requirements: инфраструктура для всех новых тестов_

  - [ ] 17.3 Валидировать `project.pbxproj` структурно
    - Файл: `TemirlanToDo.xcodeproj/project.pbxproj`
    - Запустить `plutil -lint TemirlanToDo.xcodeproj/project.pbxproj` (если доступно в CI), либо xcodebuild-список через `xcodebuild -list -project TemirlanToDo.xcodeproj` в CI-логах.
    - Проверить, что все новые id уникальны (grep дубликатов на 24-значных hex).
    - _Requirements: инфраструктура_

- [ ] 18. Финальная проверка — push на ветку и зелёный CI

  - [ ] 18.1 Прогнать локально (где возможно) и закоммитить изменения
    - Команды (если доступен `swift` без Xcode — пропустить; иначе):
      - `git status`, `git add -A`, `git commit -m "feat(task-time-and-notifications): time on tasks, local notifications, widget Next-line"`.
    - _Requirements: все_

  - [ ] 18.2 Запушить на feature-ветку и убедиться, что GitHub Actions `ios-build.yml` зелёный
    - Команда: `git push -u origin feature/task-time-and-notifications`.
    - Открыть GitHub Actions, дождаться завершения `xcodebuild test`, проверить:
      - Все существующие тесты (TaskStoreTests, TaskStorageTests, AssistantActionsTests, AssistantModelsTests) — проходят (не сломали обратной совместимости).
      - Все новые property-тесты — проходят, минимум 100 итераций каждое.
      - Все новые unit-тесты — проходят.
    - При красном CI: прочитать stack-trace и контр-пример из `XCTFail` (PBT helper выводит итерацию и serialized входной значение), исправить, перепушить.
    - _Requirements: все_

  - [ ] 18.3 Чекпойнт — Ensure all tests pass, ask the user if questions arise
    - Удостовериться, что все тесты проходят на CI. Если возникают вопросы по неоднозначностям требований — спросить пользователя перед закрытием задачи.
    - _Requirements: все_

## Notes

- Подзадачи, помеченные `*` (тесты), являются опциональными для быстрого MVP, но настоятельно рекомендуются для верификации Property-инвариантов из `design.md`.
- Топ-уровневые задачи (1-18) НЕ помечены `*` — они обязательны.
- Каждая Property ссылается на номер из секции **Correctness Properties** в `design.md` и список acceptance-критериев из `requirements.md`, которые она валидирует.
- PBT helper (`TemirlanToDoTests/PBT.swift`) использует только `XCTest` без внешних зависимостей — совместим с CI `xcodebuild test` без модификации `Package.swift`/SPM.
- Локальное редактирование `project.pbxproj` (задача 17) требует осторожности: дубликаты id ломают сборку. После задачи 17 рекомендуется немедленно запустить CI (задача 18.2) — это самый надёжный способ проверить корректность.
- Сервис `NotificationDelegate` (для подавления Morning_Digest при нуле задач из Req 6.3) реализован проще: задача 12.4 не планирует утренний дайджест при отсутствии активных задач, поэтому отдельный `UNUserNotificationCenterDelegate` не нужен.
- Все изменения сохраняют обратную совместимость с существующим JSON-хранилищем задач и существующим виджет-снапшотом (Property 2, 18).

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "2.1", "10.1", "10.3", "11.1"] },
    { "id": 1, "tasks": ["2.2", "3.1", "3.2", "3.3", "3.4", "4.1", "4.2", "5.1", "5.2", "5.3", "6.1", "6.2", "8.1", "9.1", "10.2", "11.2"] },
    { "id": 2, "tasks": ["2.3", "2.4", "2.5", "2.6", "3.5", "3.6", "3.7", "3.8", "4.3", "5.4", "6.3", "6.4", "7.1", "8.2", "8.3", "9.2", "11.3", "11.4", "11.5", "12.1", "16.1", "16.2"] },
    { "id": 3, "tasks": ["4.4", "4.5", "4.6", "6.5", "7.2", "9.3", "9.4", "12.2", "12.3", "13.1"] },
    { "id": 4, "tasks": ["7.3", "7.4", "12.4", "12.5", "12.6", "13.2", "14.1"] },
    { "id": 5, "tasks": ["12.7", "12.8", "12.9", "12.10", "12.11", "12.12", "15.1", "15.2", "15.3"] },
    { "id": 6, "tasks": ["17.1", "17.2"] },
    { "id": 7, "tasks": ["17.3", "18.1"] },
    { "id": 8, "tasks": ["18.2"] },
    { "id": 9, "tasks": ["18.3"] }
  ]
}
```
