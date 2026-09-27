# NeverWin — журнал разработки (WORK.md, ведёт AGENT 1)

> Основной рабочий журнал проекта. Перед ЛЮБЫМИ изменениями читать этот файл
> и сверяться с текущим состоянием репозитория. README.md — только про игру.

---

## AGENT 1: 27.09.2026, ~17:45, UTC+5 (Ekaterinburg Standard Time)

### Контекст и аудит перед работой
- Прочитал WORK.md — **файл отсутствовал** (создаю с нуля, это первая запись).
- Проверил `git log --oneline`: в домашнем репозитории (`C:/Users/gensh`,
  remote `Blackcrapn/Render-obrabotchik`) последние коммиты
  `cff4169 / fbbd888 / 226e5ed` касаются **только** `index.html / script.js /
  style.css` (магазин/змейка в корне). Каталог `Documents/Default Project`
  (Flutter) этими коммитами **не затронут** — изменений AGENT 2 внутри
  Flutter-проекта нет, ломать нечего. Файлы AGENT 2 в корне **не трогал**.
- `lib/` содержал только шаблонный счётчик Flutter — проект превращается
  в NeverWin с нуля.
- Логотип найден: `C:\Users\gensh\Downloads\ChatGPT Image 27 сент. 2026 г., 16_39_11.png`
  → скопирован в `assets/logo/neverwin_logo.png`, используется в шапке баланса,
  экране входа и (через `Image.asset`) по всему приложению.
- Токены: GitHub PAT из scratch — **401 Unauthorized** (протух/отозван, проверено
  3 раза через `api.github.com/user`); Supabase PAT валиден, но оба проекта
  (`bpshjsieokrcxbaffzfg`, `xtpycflwcaudxzxychsb`) в статусе **INACTIVE (paused)**.
  Вывод: пуш/релиз и живое подключение Supabase — после восстановления доступов;
  код к этому полностью готов (см. «Публикация» ниже).
- По указанию пользователя: **APK собирается в GitHub Actions, а не локально**
  (локальный `flutter analyze/test/build` в этой песочнице зависает —
  `dart analyze` висит даже на одном файле; `flutter doctor` при этом ОК,
  Android SDK 36.0.0 на месте). Workflow `.github/workflows/android-apk.yml`
  гоняет `analyze + test + build apk --release` и публикует Release 0.1.1
  с `NeverWin.apk`.

### Изменение
Реализована **первая часть NeverWin 0.1.1** целиком: Flutter-приложение
(переименовано `fz_manager` → `neverwin`, версия `0.1.1+1`), 4 мини-игры,
банк со счетами, промокоды, лидерборд, друзья + мессенджер + дуэли, настройки,
админ-панель, Supabase-схема с серверной логикой, сине-голубой Liquid-Glass UI,
нижний докбар, workflow сборки APK в Actions.

### Реализация (как именно)
- **Зависимости** (`flutter pub add`): `supabase_flutter ^2.17.2`,
  `image_picker ^1.2.3` (фото в мессенджере), `crypto ^3.0.7` (sha256 паролей
  локального режима). Существующие `provider / shared_preferences / http`
  переиспользованы, дубликатов нет.
- **Архитектура (расширяемая)**: `GameBackend` — абстрактный контракт
  (`lib/backend/game_backend.dart`); `LocalBackend` (SharedPreferences,
  офлайн-демо с теми же правилами) и `SupabaseBackend` (PostgREST+RPC+Realtime).
  Переключение — в Настройках вводом URL+anon key. `AppState` (ChangeNotifier)
  держит сессию, конфиг, уведомления, баннеры, polling+Realtime-подписки.
- **Игры, вероятности — серверная сторона** (SQL `nw_play` — авторитет;
  `LocalBackend` — зеркало тех же констант):
  - «Больше — Меньше» (мин. 1000): сначала роллится исход 50% проигрыш /
    45% выигрыш / 5% ничья, потом генерируется второе число, согласованное
    с выбором; ничья = то же число, возврат ставки; выигрыш x2.
  - «Чёрное или Белое» (мин. 1500): слоты 25/25/2, зелёный = 2/52 ≈ 3.85%
    (< 8%), x5; угаданный цвет x2.
  - «Кости: Чёт/Нечет» (мин. 500, x2) — доп. игра №1.
  - «Орёл или Решка» (мин. 500, x2) — доп. игра №2, она же дуэльная.
  - Global x2: выигрыш умножается на `global_x2_mult` (по умолч. payout x4
    вместо x2), применяется во всех играх и дуэлях.
- **Банк**: счета (название + PIN ровно 4 цифры, публичный ID 6 цифр),
  панель управления (ID/баланс/название, пополнить/вывести/перевести по ID с
  подтверждением, копирование ID), перевод шлёт получателю верхний баннер
  строго «Игрок *ник* перевёл на ваш счёт *название* *сумма NC*.» (SQL:
  `nw_bank_create/deposit/withdraw/transfer`, `SELECT ... FOR UPDATE`).
- **Промокоды**: SQL-таблица `promo_codes` (code, reward, max_global/used_global,
  max_per_user, active, valid_from/until, min_balance, metadata jsonb) +
  `promo_redemptions`, атомарный `nw_redeem_promo`; сиды `WELCOME500`, `NEVERWIN2026`;
  ввод — внизу раздела «Банк».
- **Лидерборд**: SQL-представление `v_leaderboard` (main_balance + Σ счетов),
  ТОП-10; проигранное не учитывается по построению.
- **Друзья**: заявка по нику → уведомление; принятие/отклонение с точными
  строками «*ник* принял/отклонил вашу заявку в друзья.»; удаление из друзей
  закрывает переписку (проверка дружбы на отправку).
- **Мессенджер**: текст + фото (image_picker) + эмодзи (системная клавиатура),
  только между друзьями, Realtime (Supabase-канал, локально — polling 2 c.).
- **Дуэли**: вызов друга (игра на выбор + одинаковая ставка), принятие/отклонение;
  head-to-head резолв: challenger=первая сторона (орёл/чёт/чёрное/больше),
  opponent=вторая; обе ставки списываются атомарно, победитель забирает пот
  x2 (x2 при global x2), ничья — возврат; результат сохраняется (`duels` +
  `votes jsonb` задел под голосование). SQL: `nw_duel_create/respond`.
- **Настройки**: тёмная/светлая тема, вкл/выкл уведомлений, подключение Supabase,
  demo-админ (только локальный режим), выход. Задел под язык/звук/вибрацию.
- **Админ-панель**: видна в докбаре **только** при `is_admin` (выдаётся только
  SQL: `update profiles set is_admin=true where nickname='...'`): бан/временный
  бан/разбан, выдать/списать NC, глобальное сообщение `ADMIN: ник / текст`
  (баннер 10 c., серверный cooldown 10 c. — `nw_admin_global`), переключатель
  global x2, редактор всех `game_config`-параметров.
- **Регистрация/вход**: ник (уникальный, 3–20, латиница/цифры/_), пароль +
  подтверждение; старт **5000 NC** (`start_balance` в конфиге); Supabase-режим —
  synthetic email `nick@neverwin.local` + `nw_ensure_profile` (идемпотентно).
- **UI**: сине-голубые градиенты + тёмные панели, Liquid Glass
  (`BackdropFilter` blur 18–22), плавные анимации 180–350 мс, верхний баннер,
  докбар с бейджем уведомлений; админ-вкладка скрыта от обычных юзеров.
- **Android**: `applicationId/namespace com.neverwin.app`, label `NeverWin`,
  `INTERNET + READ_MEDIA_IMAGES`, `MainActivity` переехал в
  `com.neverwin.app`; release-сборка подписана debug-ключом (CI без секретов).
- **CI** (`.github/workflows/android-apk.yml`): job `test`
  (`pub get → analyze → test`), job `build-apk`
  (`build apk --release --build-name 0.1.1`, артефакт `NeverWin.apk`),
  job `release` (тег `v0.1.1` или ручной запуск → `softprops/action-gh-release`,
  файл `NeverWin.apk`, Release **0.1.1**). Триггеры: push тега `v*` и
  `workflow_dispatch`.
- **Тесты** (`test/widget_test.dart`): 4 игры в каталоге, мин. ставки
  1000/1500/500/500, вероятность зелёного < 8%.

### Файлы
- Изменены: `pubspec.yaml` (neverwin, 0.1.1+1, assets logo, 3 новые dep),
  `lib/main.dart` (переписан), `test/widget_test.dart` (переписан),
  `android/app/build.gradle.kts` (namespace/appId), `android/.../AndroidManifest.xml`
  (label, permissions), `README.md` (переписан под игру).
- Созданы: `lib/theme.dart`, `lib/models.dart`, `lib/state/app_state.dart`,
  `lib/backend/game_backend.dart`, `lib/backend/local_backend.dart`,
  `lib/backend/supabase_backend.dart`, `lib/widgets/glass.dart`,
  `lib/widgets/dock.dart`, `lib/screens/` (auth, home_shell, games, bank,
  leaderboard, friends, settings, admin), `assets/logo/neverwin_logo.png`,
  `supabase/schema.sql`, `.github/workflows/android-apk.yml`, `WORK.md`.
- Удалены: старый `MainActivity.kt` (`com.fzmanager`), каталог `com/fzmanager`.
- НЕ тронуты: `index.html`, `script.js`, `style.css` в корне (работа AGENT 2),
  всё остальное вне `Documents/Default Project`.

### SQL
- `supabase/schema.sql` (v0.1.1, применяется целиком в SQL Editor после resume
  paused-проекта): `game_config` (24 ключа: стартовый баланс, мин. ставки,
  множители incl. green x5 и global_x2_mult, вероятности hl 50/45/5 и слоты
  25/25/2, лимиты, cooldown/TTL), `profiles`, `bank_accounts` (6-значный number,
  pin_hash), `promo_codes` + `promo_redemptions`, `friendships`, `messages`,
  `duels` (votes jsonb), `notices`, `global_messages`, `game_history`,
  `v_leaderboard`; RLS включён везде, прямых записей клиента нет (deny по
  умолчанию, чтение конфига/профилей/глобальных — authenticated); RPC
  `SECURITY DEFINER`: `nw_ensure_profile`, `nw_play`, `nw_bank_*` (4),
  `nw_redeem_promo`, `nw_friend_request/respond`, `nw_friends`, `nw_friend_remove`,
  `nw_duel_create/respond`, `nw_admin_*` (6: block/unblock/grant/take/global/set_param);
  все деньги — `SELECT ... FOR UPDATE` в одной транзакции; в конце файла —
  готовые SQL-рецепты для админа (выдать is_admin, баны, NC, параметры, гибкие
  промокоды с metadata).
- Стилистика SQL зафиксирована в шапке файла: префикс `nw_`, деньги BIGINT≥0,
  всё настраиваемое — только через `game_config`, клиент — только интент.

### Результат
- Код первой части (v0.1.1) полностью написан, тест-спецификация обновлена,
  CI-план сборки/релиза создан. Состояние: **ожидает push + запуск Actions**
  (см. «Публикация»).
- Локальная верификация ограничена песочницей (analyze/test/build виснут);
  полнота проверки переносится в CI (`flutter analyze`, `flutter test`,
  `flutter build apk --release`).

### Публикация
- GitHub PAT из scratch → 401 (недействителен), создать/пушить в репозиторий
  NeverWin из песочницы невозможно; remote домашнего репо — чужой проект
  (`Render-obrabotchik`), пушить туда NeverWin **нельзя**. Дальше — после
  восстановления токена пользователем:
  1. `gh repo create <owner>/NeverWin --public --source=.` (корень — каталог
     `Documents/Default Project`) либо push в существующий NeverWin;
  2. `git tag v0.1.1; git push origin v0.1.1` → Actions соберёт APK,
     создаст Release **0.1.1** и прикрепит **NeverWin.apk** автоматически;
     либо ручной запуск workflow (`workflow_dispatch` → `release: true`).
- Supabase: после resume проекта выполнить `supabase/schema.sql` в SQL Editor,
  затем в приложении (Настройки → Сервер) ввести URL + anon key.

---

## (следующие записи AGENT 1 / AGENT 2 — ниже, новые сверху не требуются, дописывать в конец)
