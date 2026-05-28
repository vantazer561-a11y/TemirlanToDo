# Requirements Document

## Introduction

Фича `task-time-and-notifications` расширяет приложение Temirlan To Do (SwiftUI, iOS 15+) тремя связанными возможностями:

1. **Время у задач.** К существующему полю `TaskItem.dueDate: Date?`, которое сейчас хранит только дату (полночь по локальному календарю), добавляется опциональное время дня (часы и минуты). Пользователь может задать «только дату», «дату и время» или вовсе не задавать дедлайн.
2. **Локальные уведомления.** Через `UNUserNotificationCenter` приложение отправляет два типа локальных уведомлений: ежедневное утреннее сводное уведомление о задачах на сегодня и точечные напоминания за заданное число минут до `dueDate` задач, у которых задано время.
3. **Виджет с ближайшей задачей.** Виджет «Today Tasks» (`TemirlanToDoWidget`) дополняется информацией о ближайшей задаче с точным временем на сегодня, при сохранении обратной совместимости снапшота, читаемого старыми сборками виджета.

Изменения должны быть совместимы с уже существующим JSON-хранилищем задач, AI-ассистентом, темой `CyberpunkTheme` и App Group `group.com.temirlan.todo`.

## Glossary

- **App**: основное iOS-приложение Temirlan To Do (target `TemirlanToDo`, bundle ID `com.temirlan.todo`).
- **Widget_Extension**: WidgetKit-таргет `TemirlanToDoWidget`, читающий снапшот через App Group.
- **Task**: значение типа `TaskItem`, описанное в `Models/TaskItem.swift`.
- **Due_Date**: значение поля `TaskItem.dueDate` типа `Date?`. До этой фичи всегда хранит полночь локального дня.
- **Has_Time_Flag**: новый булев атрибут `TaskItem.dueHasTime`, обозначающий, заданы ли у `Due_Date` осмысленные часы и минуты, в дополнение к календарной дате.
- **Date_Only_Task**: `Task`, у которого `Due_Date != nil` и `Has_Time_Flag == false` (дедлайн «на день»).
- **Timed_Task**: `Task`, у которого `Due_Date != nil` и `Has_Time_Flag == true` (точный момент времени).
- **Task_Store**: класс `TaskStore` (`Stores/TaskStore.swift`), отвечающий за CRUD задач и сохранение в JSON.
- **Task_Storage**: тип `TaskStorage` (`Storage/TaskStorage.swift`), отвечающий за сериализацию `[TaskItem]` в JSON.
- **Task_Detail_View**: SwiftUI-экран `TaskDetailView` для редактирования задачи.
- **Add_Task_Composer**: SwiftUI-компонент `AddTaskComposerView` для быстрого создания задачи.
- **Notification_Center**: системный `UNUserNotificationCenter`.
- **Notification_Scheduler**: новый сервис в App, инкапсулирующий планирование и отмену локальных уведомлений через `Notification_Center`.
- **Notification_Settings**: новая структура `NotificationSettings`, хранящая пользовательские настройки уведомлений (включены ли утренние уведомления, время утреннего уведомления, включены ли напоминания о задачах, lead-time в минутах).
- **Notification_Settings_View**: новый SwiftUI-экран настроек уведомлений.
- **Morning_Digest_Notification**: ежедневное локальное уведомление, которое содержит количество активных задач на сегодня и название ближайшей `Timed_Task` сегодня.
- **Task_Reminder_Notification**: точечное локальное уведомление, отправляемое за `Lead_Time_Minutes` до `Due_Date` конкретной `Timed_Task`.
- **Lead_Time_Minutes**: целое число минут до `Due_Date`, за которое отправляется `Task_Reminder_Notification`. Допустимые значения: 5, 15, 30, 60. По умолчанию 15.
- **Morning_Time**: время суток (часы и минуты) в локальной таймзоне, в которое отправляется `Morning_Digest_Notification`. По умолчанию 08:00.
- **Permission_State**: значение `UNAuthorizationStatus` для App, возвращаемое `Notification_Center`.
- **Today_Widget_Snapshot**: значение `TodayWidgetSnapshot` (`Models/TodayWidgetSnapshot.swift`), сохраняемое в App Group `group.com.temirlan.todo`.
- **Next_Timed_Task_Today**: ближайшая по времени `Timed_Task` сегодня, у которой `isCompleted == false` и `Due_Date >= now`.
- **Assistant_Action**: значение типа `AssistantAction` из `AI/AssistantModels.swift`, поле `dueDate: String?`.
- **ISO_Date_String**: строка вида `yyyy-MM-dd`, где `yyyy` — четыре цифры года, `MM` — две цифры месяца (01–12), `dd` — две цифры дня (01–31), интерпретируется в локали `en_US_POSIX`.
- **ISO_Date_Time_String**: строка вида `yyyy-MM-dd'T'HH:mm`, где `HH` — две цифры часа (00–23), `mm` — две цифры минут (00–59), без секунд и таймзоны, интерпретируется в локали `en_US_POSIX` и текущей таймзоне устройства.

## Requirements

### Requirement 1: Хранение времени у задачи

**User Story:** Как пользователь, я хочу указывать у задачи не только дату, но и точное время, чтобы получать напоминания в нужный момент дня.

#### Acceptance Criteria

1. THE Task SHALL содержать булево свойство `dueHasTime` со значением по умолчанию `false` для впервые создаваемой задачи.
2. WHEN Task сохраняется в Task_Storage, THE Task_Storage SHALL сериализовать значение `dueHasTime` в JSON как булев ключ той же задачи, и SHALL сохранять `dueDate` с точностью до минуты (секунды и наносекунды равны нулю).
3. WHEN Task_Storage загружает существующий JSON, в котором отсутствует ключ `dueHasTime`, THE Task_Storage SHALL декодировать такую задачу с `dueHasTime == false`, и значение `dueDate` SHALL остаться без изменений относительно сохранённого в JSON.
4. WHEN Task_Storage загружает задачу, у которой `dueDate == nil`, THE Task_Storage SHALL установить `dueHasTime` в `false` независимо от значения, присутствующего в JSON.
5. IF приложение пытается установить у задачи `dueHasTime == true`, в то время как `dueDate == nil`, THEN THE Task_Store SHALL установить `dueHasTime` в `false` перед сохранением.
6. WHEN пользователь устанавливает время у задачи с заданной датой, THE Task_Store SHALL сохранить указанные час и минуту в `dueDate` (секунды и наносекунды равны нулю) в локальной таймзоне устройства и установить `dueHasTime` в `true`.
7. WHEN пользователь очищает время у задачи, не удаляя дату, THE Task_Store SHALL установить `dueHasTime` в `false`, нормализовать `dueDate` к началу локального дня устройства (час, минута, секунда и наносекунда равны нулю) и сохранить задачу.
8. WHEN пользователь полностью убирает дедлайн (Due date выключен), THE Task_Store SHALL установить `dueDate = nil`, `dueHasTime = false` и сохранить задачу.

### Requirement 2: Редактирование времени в `TaskDetailView`

**User Story:** Как пользователь, я хочу в экране редактирования задачи отдельно включать дату и время, чтобы было ясно, есть ли у задачи точка в расписании.

#### Acceptance Criteria

1. THE Task_Detail_View SHALL содержать тумблер `Add time`, расположенный в той же секции, что и тумблер `Due date`, и отображаемый во всех состояниях экрана без скрытия (включая состояния, когда `Due date` выключен или включён).
2. WHILE тумблер `Due date` выключен, THE Task_Detail_View SHALL отображать тумблер `Add time` в выключенном и недоступном для взаимодействия (`disabled`) состоянии, SHALL принудительно устанавливать `dueHasTime = false`, и SHALL не отображать `DatePicker` времени.
3. WHEN тумблер `Due date` включается у задачи, у которой `dueDate == nil`, THE Task_Detail_View SHALL установить `dueDate` в текущую локальную дату с обнулёнными часами, минутами, секундами и наносекундами и установить `dueHasTime` в `false`.
4. WHEN тумблер `Add time` включается у задачи с заданной датой, THE Task_Detail_View SHALL установить `dueHasTime` в `true` и инициализировать `dueDate` ближайшим следующим строго будущим моментом локального времени, у которого минуты делятся на 15 без остатка и секунды и наносекунды равны нулю; если такой ближайший момент приходится на следующий локальный день (например, текущее время 23:50 → следующий 00:00), календарная дата `dueDate` сдвигается на этот следующий день.
5. WHILE тумблер `Add time` включён, THE Task_Detail_View SHALL отображать `DatePicker`, привязанный к `dueDate`, с `displayedComponents == .hourAndMinute`.
6. WHEN пользователь выключает тумблер `Add time` (при включённом `Due date`), THE Task_Detail_View SHALL установить `dueHasTime` в `false` и нормализовать `dueDate` к началу того же локального дня (час, минута, секунда, наносекунда = 0) без изменения календарной даты.
7. WHEN пользователь нажимает `Done` в Task_Detail_View, THE Task_Store SHALL сохранить задачу с актуальными значениями `dueDate` и `dueHasTime`, так что повторное открытие той же задачи отобразит те же значения.
8. WHEN Task_Detail_View открывается на задаче с `dueHasTime == true`, THE Task_Detail_View SHALL отобразить тумблер `Add time` во включённом состоянии и `DatePicker` времени, инициализированный значением `dueDate`.
9. WHEN Task_Detail_View открывается на задаче с `dueDate != nil` и `dueHasTime == false`, THE Task_Detail_View SHALL отобразить тумблер `Add time` в выключенном, но доступном для взаимодействия состоянии, и SHALL не отображать `DatePicker` времени.

### Requirement 3: Отображение времени в списке задач

**User Story:** Как пользователь, я хочу видеть время задачи прямо в списке, чтобы понимать, на какой час назначен дедлайн.

#### Acceptance Criteria

1. WHEN Task имеет `dueDate != nil` и `dueHasTime == false`, THE App SHALL отображать в строке задачи только локальную дату в коротком стиле текущей локали устройства (эквивалент `DateFormatter.Style.short`, например `27.05.26` для русской локали или `5/27/26` для en_US), без отображения времени.
2. WHEN Task имеет `dueDate != nil` и `dueHasTime == true`, THE App SHALL отображать в строке задачи локальную дату в коротком стиле текущей локали и локальное время в формате часов и минут текущей локали (12- или 24-часовой формат определяется локалью; например `27.05.26, 14:30` для русской локали и `5/27/26, 2:30 PM` для en_US), причём время идёт после даты и отделяется запятой и пробелом.
3. WHEN Task имеет `dueDate == nil`, THE App SHALL не отображать в строке задачи ни дату, ни время, ни любой плейсхолдер или разделитель, относящийся к дате/времени.
4. THE App SHALL форматировать `dueDate` и для даты, и для времени относительно текущей таймзоны устройства, так что один и тот же `dueDate` (моментарный `Date`) отображается согласно настройкам таймзоны системы.
5. WHEN текущая локаль или таймзона устройства изменяется, THE App SHALL перерисовать строки задач так, чтобы дата и время отображались по новой локали и таймзоне без перезапуска приложения.

### Requirement 4: Совместимость AI-ассистента с временем

**User Story:** Как пользователь AI-ассистента, я хочу, чтобы ассистент мог задавать задачам не только дату, но и точное время, при этом старые ответы с одной только датой продолжали работать.

#### Acceptance Criteria

1. THE Assistant_Action SHALL принимать поле `dueDate` в одном из трёх вариантов: ISO_Date_String (`yyyy-MM-dd`, `MM` ∈ 01–12, `dd` ∈ 01–31), ISO_Date_Time_String (`yyyy-MM-dd'T'HH:mm`, `HH` ∈ 00–23, `mm` ∈ 00–59) или `null`.
2. WHEN Task_Store применяет Assistant_Action с `dueDate` в формате ISO_Date_String, THE Task_Store SHALL установить `dueDate` в момент 00:00:00.000 указанной календарной даты в текущем часовом поясе устройства и установить `dueHasTime` в `false`.
3. WHEN Task_Store применяет Assistant_Action с `dueDate` в формате ISO_Date_Time_String, THE Task_Store SHALL установить `dueDate` в момент с указанными часом и минутой указанной календарной даты, секундами равными нулю, в текущем часовом поясе устройства, и установить `dueHasTime` в `true`.
4. WHEN Task_Store применяет Assistant_Action с `dueDate == null`, THE Task_Store SHALL установить `dueDate = nil` и `dueHasTime = false` целевой задачи.
5. THE App SHALL описывать в JSON-схеме, передаваемой Fireworks, что поле `dueDate` принимает строку в формате `yyyy-MM-dd`, строку в формате `yyyy-MM-dd'T'HH:mm` или значение `null`.
6. IF Task_Store применяет Assistant_Action с `dueDate`, не соответствующим ни ISO_Date_String, ни ISO_Date_Time_String, ни `null`, THEN THE Task_Store SHALL не изменять значения `dueDate` и `dueHasTime` целевой задачи, SHALL зафиксировать ошибку валидации `dueDate`, наблюдаемую через существующий механизм ошибок (например, `lastErrorMessage`), и SHALL продолжить применение остальных полей текущего Assistant_Action и последующих Assistant_Action из той же партии без прерывания.

### Requirement 5: Запрос разрешения на уведомления

**User Story:** Как пользователь, я хочу однократно дать разрешение на уведомления и видеть понятное сообщение, если я отказал, чтобы я мог открыть системные настройки и изменить решение.

#### Acceptance Criteria

1. WHEN пользователь открывает Notification_Settings_View и Permission_State равен `.notDetermined`, THE App SHALL запросить у Notification_Center авторизацию с опциями `[.alert, .sound]`.
2. WHEN пользователь включает любой тумблер уведомлений в Notification_Settings_View и Permission_State равен `.notDetermined`, THE App SHALL запросить у Notification_Center авторизацию с опциями `[.alert, .sound]` до сохранения настройки.
3. IF запрос авторизации к Notification_Center завершился с ошибкой, THEN THE App SHALL не изменять значения тумблеров и параметров уведомлений, SHALL не вызывать методы планирования у Notification_Scheduler и SHALL отобразить пользователю индикатор ошибки в Notification_Settings_View.
4. WHILE Permission_State равен `.denied`, THE Notification_Settings_View SHALL отображать сообщение «Разрешение на уведомления отключено» в верхней части экрана и кнопку «Открыть настройки iOS», и SHALL отображать тумблеры уведомлений в недоступном для взаимодействия состоянии.
5. WHEN пользователь нажимает кнопку «Открыть настройки iOS» в Notification_Settings_View, THE App SHALL открыть URL `UIApplication.openSettingsURLString` в течение 1 секунды.
6. WHILE Permission_State равен `.denied`, THE Notification_Scheduler SHALL не вызывать методы планирования у Notification_Center, SHALL не выбрасывать ошибок при таких пропусках, и SHALL сохранять состояние ранее запланированных уведомлений неизменным.
7. WHEN App переходит в активное состояние из фона, THE App SHALL запросить у Notification_Center актуальный Permission_State.
8. WHEN Permission_State меняется с `.denied` на `.authorized`, THE App SHALL перепланировать в течение 5 секунд все уведомления, для которых соответствующий тумблер настроек включён и момент срабатывания ещё не наступил.

### Requirement 6: Утреннее сводное уведомление

**User Story:** Как пользователь, я хочу одно утреннее уведомление со сводкой по задачам на сегодня, чтобы быстро понимать предстоящий день.

#### Acceptance Criteria

1. THE Notification_Settings SHALL содержать булево поле `morningDigestEnabled` со значением по умолчанию `true` и поле `morningTime` типа `DateComponents` (только `hour` в диапазоне 0–23 и `minute` в диапазоне 0–59) со значением по умолчанию `hour = 8`, `minute = 0`, интерпретируемое в локальной таймзоне устройства.
2. WHILE `morningDigestEnabled == true` и Permission_State равен `.authorized`, THE Notification_Scheduler SHALL поддерживать ровно один запланированный повторяющийся Morning_Digest_Notification с триггером `UNCalendarNotificationTrigger` на основе `Calendar.current` в локальной таймзоне устройства, у которого `dateComponents.hour == morningTime.hour`, `dateComponents.minute == morningTime.minute`, `repeats == true`, и SHALL отменять любые ранее запланированные Morning_Digest_Notification перед регистрацией нового, так что итоговое количество запланированных Morning_Digest_Notification равно 1.
3. WHEN наступает запланированное время доставки Morning_Digest_Notification и количество активных задач на сегодня (задач, для которых `isCompleted == false` и `TaskListKind.myDay.contains(task)` истинно относительно текущей даты в локальной таймзоне устройства) равно 0, THE Notification_Scheduler SHALL предотвратить отображение Morning_Digest_Notification пользователю, так что от данного уведомления не появляются ни баннер, ни звук, ни инкремент badge.
4. WHEN Morning_Digest_Notification доставляется и количество активных задач на сегодня (N) больше 0, THE Notification_Scheduler SHALL установить заголовок уведомления равным `Сегодня <N> <словоформа>`, где `<словоформа>` выбирается по русским правилам склонения для числа N: `задача`, если `N % 10 == 1` и `N % 100` не входит в диапазон 11–14; `задачи`, если `N % 10` входит в множество {2, 3, 4} и `N % 100` не входит в диапазон 11–14; во всех остальных случаях `задач`.
5. WHEN Morning_Digest_Notification доставляется и существует Next_Timed_Task_Today, THE Notification_Scheduler SHALL установить тело уведомления равным `Ближайшая: <название> в <HH:mm>`, где `<HH:mm>` — время `dueDate` Next_Timed_Task_Today в локальной таймзоне устройства в 24-часовом формате с двумя цифрами часа и двумя цифрами минут с ведущими нулями, а `<название>` — значение поля `title` Next_Timed_Task_Today без модификаций.
6. WHEN Morning_Digest_Notification доставляется, Next_Timed_Task_Today отсутствует и количество активных задач на сегодня больше 0, THE Notification_Scheduler SHALL установить тело уведомления равным `Ближайшая: <название>`, где `<название>` — значение поля `title` задачи, детерминированно выбранной по следующему порядку: (а) если хотя бы одна активная задача на сегодня имеет `dueDate`, выбирается задача с самым ранним `dueDate`; при равенстве `dueDate` побеждает задача с самым поздним `createdAt`; при равенстве `createdAt` побеждает задача с наименьшим лексикографическим значением `id.uuidString`; (б) если ни у одной активной задачи на сегодня нет `dueDate`, выбирается задача с самым поздним `createdAt`; при равенстве `createdAt` побеждает задача с наименьшим лексикографическим значением `id.uuidString`.
7. WHILE `morningDigestEnabled == false` или Permission_State не равен `.authorized`, THE Notification_Scheduler SHALL отменять любые ранее запланированные Morning_Digest_Notification, так что количество запланированных Morning_Digest_Notification равно 0.
8. WHEN пользователь сохраняет новое валидное значение `morningTime` (`hour` ∈ 0..23, `minute` ∈ 0..59) в Notification_Settings_View и `morningDigestEnabled == true` и Permission_State равен `.authorized`, THE Notification_Scheduler SHALL отменить ранее запланированный Morning_Digest_Notification и запланировать новый с обновлёнными `dateComponents.hour` и `dateComponents.minute`, так что итоговое состояние содержит ровно один Morning_Digest_Notification со временем срабатывания, соответствующим новому `morningTime`.

### Requirement 7: Напоминания о ближайших задачах с временем

**User Story:** Как пользователь, я хочу получать локальное напоминание за заданное число минут до времени задачи, чтобы не пропускать дедлайны с точной привязкой к часам.

#### Acceptance Criteria

1. THE Notification_Settings SHALL содержать булево поле `taskRemindersEnabled` со значением по умолчанию `true` и поле `leadTimeMinutes` типа `Int` со значением по умолчанию `15` и допустимыми значениями из множества `{5, 15, 30, 60}`.
2. IF `leadTimeMinutes` устанавливается в значение, не входящее в `{5, 15, 30, 60}`, THEN THE Notification_Settings SHALL отвергнуть это значение и сохранить предыдущее.
3. WHILE `taskRemindersEnabled == true` и Permission_State равен `.authorized`, для каждой Timed_Task с `isCompleted == false` и `Due_Date − Lead_Time_Minutes > now`, THE Notification_Scheduler SHALL поддерживать запланированный Task_Reminder_Notification с триггером `UNCalendarNotificationTrigger` на основе локальной таймзоны устройства (`repeats == false`), у которого момент срабатывания равен `Due_Date − Lead_Time_Minutes`.
4. WHEN Notification_Scheduler планирует Task_Reminder_Notification, THE Notification_Scheduler SHALL использовать идентификатор запроса вида `task-reminder.<TaskItem.id>` для возможности повторного планирования.
5. THE Notification_Scheduler SHALL устанавливать заголовок Task_Reminder_Notification равным заголовку соответствующей Task и тело равным `Через <Lead_Time_Minutes> мин в <HH:mm>`, где `<HH:mm>` — локальное время Due_Date в 24-часовом формате с ведущими нулями.
6. WHEN Task создаётся, обновляется, удаляется или помечается выполненной/невыполненной через Task_Store, THE Notification_Scheduler SHALL отменить и при необходимости заново запланировать соответствующий Task_Reminder_Notification.
7. IF Task становится Date_Only_Task (`dueHasTime` стал `false`) или у Task становится `dueDate == nil`, THEN THE Notification_Scheduler SHALL отменить ранее запланированный Task_Reminder_Notification для этой Task.
8. IF `Due_Date − Lead_Time_Minutes <= now` для Timed_Task, THEN THE Notification_Scheduler SHALL не планировать Task_Reminder_Notification для этой Task.
9. WHEN `taskRemindersEnabled` меняется с `true` на `false`, THE Notification_Scheduler SHALL отменить все ранее запланированные Task_Reminder_Notification.
10. WHEN `leadTimeMinutes` меняется на новое валидное значение, THE Notification_Scheduler SHALL отменить все ранее запланированные Task_Reminder_Notification и заново запланировать их по правилам пункта 3 с новым значением Lead_Time_Minutes.
11. WHEN App переходит в активное состояние, THE Notification_Scheduler SHALL синхронизировать запланированные Task_Reminder_Notification с актуальным состоянием задач, удаляя запросы для несуществующих, выполненных или потерявших время задач.
12. WHEN Permission_State становится не равным `.authorized`, THE Notification_Scheduler SHALL отменить все ранее запланированные Task_Reminder_Notification и не планировать новые до восстановления `.authorized`.
13. IF количество кандидатов на планирование Task_Reminder_Notification превышает iOS-лимит в 64 одновременных pending-запроса (вместе с Morning_Digest_Notification), THEN THE Notification_Scheduler SHALL планировать запросы в порядке возрастания `Due_Date` и пропускать самые поздние, чтобы не превысить лимит.

### Requirement 8: Экран настроек уведомлений

**User Story:** Как пользователь, я хочу один экран, где можно включать утренние уведомления и напоминания о задачах и выбирать их параметры, чтобы управлять поведением уведомлений в одном месте.

#### Acceptance Criteria

1. THE App SHALL предоставлять Notification_Settings_View, доступный с главного экрана через видимую кнопку настроек уведомлений (например, иконку «bell» в навигационной панели).
2. THE Notification_Settings_View SHALL содержать тумблер `Morning summary`, привязанный к `morningDigestEnabled`.
3. WHILE `morningDigestEnabled == true`, THE Notification_Settings_View SHALL отображать `DatePicker` с `displayedComponents == .hourAndMinute`, привязанный к `morningTime`, в формате час и минута 24-часового представления в локальной часовой зоне устройства.
4. WHILE `morningDigestEnabled == false`, THE Notification_Settings_View SHALL не отображать `DatePicker`, привязанный к `morningTime`.
5. THE Notification_Settings_View SHALL содержать тумблер `Task reminders`, привязанный к `taskRemindersEnabled`.
6. WHILE `taskRemindersEnabled == true`, THE Notification_Settings_View SHALL отображать `Picker` со значениями `5`, `15`, `30`, `60` минут, привязанный к `leadTimeMinutes`.
7. WHILE `taskRemindersEnabled == false`, THE Notification_Settings_View SHALL не отображать `Picker`, привязанный к `leadTimeMinutes`.
8. WHEN пользователь меняет любую настройку в Notification_Settings_View, THE App SHALL сначала сохранить актуальные Notification_Settings в `UserDefaults` и только после успешного сохранения, не позднее 1 секунды, вызвать перепланирование уведомлений в Notification_Scheduler.
9. IF сохранение Notification_Settings в `UserDefaults` завершилось ошибкой, THEN THE App SHALL не вызывать перепланирование, SHALL сохранить предыдущие значения Notification_Settings в памяти и SHALL отобразить пользователю индикатор ошибки в Notification_Settings_View.
10. WHEN App запускается и в `UserDefaults` отсутствуют сохранённые Notification_Settings или сохранённые значения некорректны (`leadTimeMinutes` вне `{5, 15, 30, 60}` или `morningTime` непарсится в `hour` ∈ 0..23 и `minute` ∈ 0..59), THE App SHALL использовать значения по умолчанию (`morningDigestEnabled == true`, `morningTime == 08:00` в локальной таймзоне устройства, `taskRemindersEnabled == true`, `leadTimeMinutes == 15`) и не сохранять их до явного действия пользователя.

### Requirement 9: Виджет с ближайшей задачей

**User Story:** Как пользователь виджета на домашнем экране, я хочу видеть количество задач на сегодня и ближайшую задачу с точным временем, чтобы быстро узнать, что предстоит.

#### Acceptance Criteria

1. THE Today_Widget_Snapshot SHALL содержать опциональное поле `nextTimedTitle: String?` и опциональное поле `nextTimedDate: Date?`.
2. WHEN Task_Store сохраняет Today_Widget_Snapshot, THE Task_Store SHALL определять Next_Timed_Task_Today как задачу с наименьшим значением `dueDate` среди задач, удовлетворяющих всем условиям: `isCompleted == false`, `dueDate != nil`, `dueHasTime == true`, и `dueDate` приходится на текущий календарный день в локальной таймзоне устройства, и `dueDate >= now`.
3. IF две или более задачи удовлетворяют условиям Next_Timed_Task_Today и имеют одинаковое значение `dueDate`, THEN THE Task_Store SHALL выбирать в качестве Next_Timed_Task_Today задачу с лексикографически наименьшим `id.uuidString`, обеспечивая детерминированный выбор.
4. WHEN Task_Store сохраняет Today_Widget_Snapshot и существует Next_Timed_Task_Today, THE Task_Store SHALL установить `nextTimedTitle` равным заголовку Next_Timed_Task_Today, обрезанному до первых 80 символов без добавления многоточия, и `nextTimedDate` равным `dueDate` Next_Timed_Task_Today.
5. WHEN Task_Store сохраняет Today_Widget_Snapshot и Next_Timed_Task_Today отсутствует, THE Task_Store SHALL установить `nextTimedTitle = nil` и `nextTimedDate = nil`.
6. WHEN Widget_Extension декодирует Today_Widget_Snapshot, в котором отсутствуют ключи `nextTimedTitle` и `nextTimedDate`, THE Widget_Extension SHALL декодировать снапшот без ошибок и считать значения этих полей равными `nil`.
7. WHILE `nextTimedTitle != nil` и `nextTimedDate != nil`, THE Widget_Extension SHALL отображать строку «Next: <название> в <HH:mm>», где `<HH:mm>` — представление `nextTimedDate` в 24-часовом формате с ведущими нулями (диапазон часов 00–23, минут 00–59) в локальном часовом поясе устройства, в дополнение к существующему счётчику задач и списку заголовков.
8. WHILE `nextTimedTitle == nil` или `nextTimedDate == nil`, THE Widget_Extension SHALL не отображать строку про ближайшую задачу и сохранять текущее поведение виджета.
9. WHEN Task_Store завершает сохранение Today_Widget_Snapshot, THE Task_Store SHALL вызвать `WidgetCenter.shared.reloadTimelines(ofKind: "TemirlanToDoWidget")` ровно один раз за операцию сохранения.

### Requirement 10: Совместимость существующих данных

**User Story:** Как пользователь с уже установленным приложением, я хочу, чтобы после обновления мои существующие задачи остались доступны и корректно вели себя без точного времени, чтобы я не потерял данные.

#### Acceptance Criteria

1. WHEN App запускается и читает структурно валидный существующий JSON задач, не содержащий ключа `dueHasTime` ни у одной задачи, THE Task_Storage SHALL загрузить такие задачи без выбрасывания исключений и SHALL установить `dueHasTime = false` у каждой загруженной задачи независимо от того, содержит ли её поле `dueDate` ненулевые часы или минуты.
2. WHEN App запускается и Widget_Extension читает существующий снапшот виджета, не содержащий ключей `nextTimedTitle` и `nextTimedDate`, THE Widget_Extension SHALL декодировать снапшот без выбрасывания исключений и интерпретировать значения этих полей как `nil` (отсутствие ближайшей задачи с временем).
3. WHEN App впервые сохраняет задачи после обновления, THE Task_Storage SHALL записать JSON, в котором у каждой задачи присутствует ключ `dueHasTime`, и для задач, ранее загруженных без этого ключа, его значение SHALL быть `false`.
4. THE App SHALL сохранять `dueDate` в JSON стандартным `JSONEncoder` (как ISO 8601-`Date`), и при миграции существующих задач к новой схеме SHALL не модифицировать значения `dueDate` относительно того, что было сохранено в JSON.
5. IF JSON задач содержит структурные ошибки (некорректные типы полей или нарушенный JSON-синтаксис), THEN THE Task_Storage SHALL пробросить ошибку декодирования через существующий механизм `loadTasks()`, SHALL не возвращать пустой или частично заполненный массив без сигнализации, и SHALL не подменять ошибку молчаливым значением по умолчанию.
