# Telemt: как он взаимодействует с клиентом и с серверами Telegram

> Режим: **DOC + TEST**.  
> Этот материал основан на исходниках и документации в репозитории `projects/telegram/telemt`.

## 1) Что такое Telemt в этой архитектуре

`telemt` — это MTProxy-сервер на Rust/Tokio, который:

1. Принимает клиентские подключения Telegram (`Classic`, `Secure/dd`, `FakeTLS/ee`).
2. После аутентификации клиента маршрутизирует трафик либо:
   - в **Middle-End / Middle Proxy** (основной путь при `use_middle_proxy=true`),
   - либо напрямую в **Telegram DC** (direct mode).
3. Для невалидных/чужих TLS-подключений может не раскрывать себя как прокси, а работать как L4 TCP relay на `mask_host:mask_port` (маскировка).

## 2) Как Telemt взаимодействует с клиентом

### 2.1 Вход и классификация клиента

На входе обработчик клиента (`ClientHandler`) читает первые байты, определяет тип handshake и пытается пройти MTProxy-аутентификацию.

Логика по сути делится на 2 ветки:

- **Валидный MTProxy клиент** → формируется `HandshakeSuccess`, поднимается relay-фаза.
- **Невалидный или не-MTProxy клиент** → обработка через masking (если включено) или закрытие/ошибка.

### 2.2 Какие клиентские режимы поддерживаются

Через `general.modes` доступны 3 официальных режима MTProxy:

- `classic`
- `secure` (dd)
- `tls` (ee / FakeTLS)

Это явно отражено и в конфиге, и в README.

### 2.3 Что происходит в FakeTLS режиме

В `ee` режиме используется fake TLS handshake (TLS-подобный), который выглядит как TLS 1.3-поток, но внутри несёт MTProxy-аутентификационные данные. Модуль `protocol/tls.rs` прямо описывает эту цель.

Важно: это не «обычный HTTPS-терминатор», а протокольная маскировка для MTProxy.

### 2.4 Что происходит после handshake клиента

После успешной аутентификации Telemt переходит к relay между:

- клиентским шифрованным потоком (`CryptoReader/CryptoWriter`),
- и апстримом (ME или Direct DC).

Для direct relay есть отдельный handshake к Telegram стороне (`do_tg_handshake_static`), затем двунаправленная передача данных.

---

## 3) Как Telemt взаимодействует с серверами Telegram

Нужно разделять **два класса взаимодействий**.

### 3.1 Контрольные служебные запросы (Control Plane)

Telemt запрашивает у Telegram инфраструктурные данные:

- `getProxySecret` (бинарный proxy-secret для ME-аутентификации), по умолчанию `https://core.telegram.org/getProxySecret`
- `getProxyConfig` (карта middle proxy endpoints, IPv4), по умолчанию `https://core.telegram.org/getProxyConfig`
- `getProxyConfigV6` (карта middle proxy endpoints, IPv6), по умолчанию `https://core.telegram.org/getProxyConfigV6`

По коду видно:

- сначала пытается скачать свежие данные,
- затем кэширует их на диск,
- при ошибках может fallback-нуться на кэш,
- при `me2dc_fallback=true` может уйти из ME в direct-mode вместо бесконечных ретраев.

### 3.2 Data Plane: транспорт пользовательского трафика

#### Вариант A: через Middle-End / Middle Proxy

Если `general.use_middle_proxy=true` и ME инициализирован:

- Telemt строит пул ME-соединений (`MePool`),
- использует карту endpoint-ов из `proxy_for` строк (из `getProxyConfig*`),
- маршрутизирует клиентские сессии через registry/bind к writer-каналам,
- применяет policy-механики (adaptive/static floor, warm standby, reinit/hardswap и т.д.).

#### Вариант B: direct в Telegram DC

В direct-режиме Telemt подключается к Telegram DC адресу, выполняет TG-handshake и дальше делает relay.

Когда прямой маршрут нужен:

- `use_middle_proxy=false`, либо
- ME временно недоступен и включён `me2dc_fallback`.

Также важно разделять, куда уходят исходящие соединения Telemt:

- к `core.telegram.org` по HTTPS — только за служебными snapshot/secret;
- к ME endpoint-ам из `proxy_for` — для Middle route;
- к Telegram DC IP:порт — для Direct route;
- к `mask_host:mask_port` (или `mask_unix_sock`) — только для маскировочного fallback-пути невалидных/чужих TLS-подключений.

---

## 4) Как Telemt получает адреса серверов Telegram

### 4.1 Адреса для Middle Proxy (ME)

Источник адресов: `getProxyConfig` / `getProxyConfigV6`.

- Парсер читает строки `proxy_for <dc> <ip:port>;` (например, `proxy_for 4 91.108.4.195:8888;` или `proxy_for 2 [2001:67c:04e8:f002::d]:80;`).
- Результат хранится в map: `dc -> [(ip,port)...]`.
- Дополнительно может читаться `default <dc>;`.

Это и есть рабочая карта endpoint-ов для `MePool`.

### 4.2 Адреса Telegram DC для direct-маршрута

Используются:

1. `dc_overrides` из конфига (если оператор явно переопределил; это приоритетный источник для direct).
2. Встроенные таблицы констант (`TG_DATACENTERS_V4`, `TG_DATACENTERS_V6`, порт 443), если override не задан.
3. Если получение свежих данных для ME не удалось, Telemt может использовать локальные кэши snapshot/secret (`proxy_config_cache_v4_path`, `proxy_config_cache_v6_path`, `proxy_secret_cache_path`) для сохранения работоспособности маршрутизации.

Для нестандартных DC действует fallback на default cluster (в коде видна логика по умолчанию на DC2 при маппинге индекса в ряде путей).

### 4.3 DNS/резолвинг

Для hostname-подключений задействованы:

- `network.dns_overrides` (если задано),
- иначе обычный DNS lookup.

---

## 5) Какие протоколы используются

Ниже разложено по каналам взаимодействия.

### 5.1 Клиент ↔ Telemt

- Транспорт: **TCP**.
- Протокол на уровне прокси: **MTProxy / MTProto proxy modes**:
  - Classic,
  - Secure (dd),
  - FakeTLS (ee).
- Для `ee`: TLS-like handshake (маскировочный формат, не обычный HTTPS termination).

### 5.2 Telemt ↔ Telegram (служебные загрузки)

- **HTTPS (HTTP/1.1 over TLS)** — это видно по `https_get` и TLS-клиентской конфигурации в `http_fetch.rs`.
- Используется для получения `getProxySecret` и `getProxyConfig*`.

### 5.3 Telemt ↔ Telegram (передача пользовательского трафика)

- В direct-режиме: TCP до Telegram DC + Telegram proxy handshake + relay.
- В ME-режиме: Telegram Middle Proxy RPC/transport (реализовано в `transport/middle_proxy/*`).

> Важно: репозиторий подробно описывает механику маршрутизации и KDF-инварианты, но не документирует «внешней спецификацией» все wire-детали внутренних Telegram протоколов. Поэтому корректно говорить на уровне ролей: ME RPC transport и TG/DC handshake, как они названы в коде.

### 5.4 API: внешние Telegram endpoint-ы и внутренний API Telemt

Чтобы не путать термины «API», здесь есть два независимых уровня:

1. Внешние Telegram HTTP endpoint-ы (`getProxySecret`, `getProxyConfig`, `getProxyConfigV6`) — источник служебных данных для инициализации/обновления ME.
2. Внутренний admin/runtime API Telemt (`[server.api]`, legacy-алиас `[server.admin_api]`) — интерфейс управления и наблюдения за самим Telemt.

---

## 6) Какие есть режимы для каждого вида взаимодействия

Ниже — практическая матрица.

## 6.1 Для клиентского входа (Client → Telemt)

1. **Classic mode** (`general.modes.classic=true`)
2. **Secure mode** (`general.modes.secure=true`)
3. **TLS/FakeTLS mode** (`general.modes.tls=true`)

Эти режимы можно включать/выключать конфигурацией.

## 6.2 Для реакции на невалидный/чужой TLS

Определяется в секции censorship:

- **Masking / TCP-Splitting** (`mask=true`): проксирование на `mask_host:mask_port`.
- Также в параметрах есть ветки поведения для неизвестного SNI (например, reject_handshake), описанные в `CONFIG_PARAMS`.

То есть тут режимы не MTProxy-функции, а anti-censorship поведение внешнего контура.

## 6.3 Для маршрута к Telegram (Telemt → Telegram Data Plane)

1. **Middle route** (`RelayRouteMode::Middle`): через `MePool`.
2. **Direct route** (`RelayRouteMode::Direct`): напрямую к DC.

Переключение управляется runtime-контроллером маршрута и admission/policy логикой.

## 6.4 Для доступности маршрута при проблемах ME

- **Fallback включён** (`me2dc_fallback=true`): при проблемах ME сервер допускает direct-route.
- **Fallback выключен** (`me2dc_fallback=false`): пытается удержать ME-путь и ретраить инициализацию/обновление.

## 6.5 Для ME orchestration

Ключевые режимы policy внутри ME:

- `me_floor_mode`: `static` или `adaptive`.
- `me_route_no_writer_mode`: `async_recovery_failfast`, `inline_recovery_legacy`, `hybrid_async_persistent`.
- `me_writer_pick_mode`: `sorted_rr` или `p2c`.

Это не «сетевые протоколы», а режимы управления пулом и поведением при дефиците writer-ов.


## 6.6 Типовые сценарии эксплуатации

### Сценарий A: валидный клиент, штатный ME-путь

1. Клиент подключается к `server.bind_to:server.port` и проходит MTProxy/FakeTLS handshake.
2. Telemt выбирает `RelayRouteMode::Middle`.
3. Endpoint выбирается из карты `proxy_for` (полученной из `getProxyConfig*`).
4. Сессия обслуживается через writer-путь пула `MePool`.

### Сценарий B: ME недоступен, включён fallback

1. Handshake клиента успешен, но ME-путь не готов/деградирован.
2. При `me2dc_fallback=true` Telemt переключает сессию на `RelayRouteMode::Direct`.
3. Выполняется direct TG-handshake, далее обычный relay напрямую к DC.

### Сценарий C: невалидный TLS/probing при включённой маскировке

1. Входной поток не подтверждается как валидный MTProxy/FakeTLS.
2. Если `censorship.mask=true`, Telemt идёт на `mask_host:mask_port` (или `mask_unix_sock`) и работает как L4 relay.
3. Снаружи это выглядит как обычная TLS-сессия к маскировочному backend.

### Сценарий D: недоступны Telegram endpoint-ы обновления

1. Попытки загрузить `getProxySecret`/`getProxyConfig*` по HTTPS завершаются ошибкой.
2. Telemt пытается взять валидный snapshot/secret из файлов кэша.
3. Итоговая доступность маршрутов зависит от наличия кэша и настроек fallback/policy.

## 6.7 Параметры, которые управляют описанными режимами

- Маршрутизация и отказоустойчивость: `general.use_middle_proxy`, `general.me2dc_fallback`, `general.prefer_ipv6_for_tg`, `general.dc_overrides`.
- Источники и кэш Telegram-данных: `general.proxy_secret_url`, `general.proxy_config_v4_url`, `general.proxy_config_v6_url`, `general.proxy_secret_cache_path`, `general.proxy_config_cache_v4_path`, `general.proxy_config_cache_v6_path`, `general.me_snapshot_min_proxy_for_lines`.
- Клиентские режимы: `general.modes.classic`, `general.modes.secure`, `general.modes.tls`.
- DNS/резолвинг: `network.dns_overrides`.
- Маскировка: `censorship.mask`, `censorship.mask_host`, `censorship.mask_port`, `censorship.mask_unix_sock`, `censorship.unknown_sni_policy`.
- Операционный API Telemt: `[server.api]` (или legacy `[server.admin_api]`).

---


## 7) Ответы на ваши вопросы в коротком виде

### Как telemt взаимодействует с клиентом?

Через TCP; принимает MTProxy handshake (classic/secure/fakeTLS), проверяет секрет пользователя, после успеха запускает relay. Невалидные TLS-клиенты могут быть замаскированы через TCP-Splitting на `mask_host`.

### Как telemt взаимодействует с серверами Telegram?

- Служебно: по HTTPS запрашивает `getProxySecret` и `getProxyConfig*`.
- Для трафика: либо через ME (Middle Proxy пул), либо direct к Telegram DC.

### Как получает адреса серверов Telegram?

- Для ME: из `getProxyConfig*` (строки `proxy_for ...`).
- Для direct DC: из встроенных таблиц DC + возможные `dc_overrides`.
- Для host-резолва учитывает `network.dns_overrides`.

### Какие протоколы используются?

- Клиентский вход: MTProxy modes over TCP (включая FakeTLS-like формат).
- Служебные загрузки: HTTPS.
- Апстрим трафика: direct DC transport / Middle Proxy transport.

### Какие есть режимы для каждого вида взаимодействия?

- Клиентские: classic / secure / tls(fakeTLS).
- Маскировка не-MTProxy: mask/tcp-splitting и политики unknown SNI.
- Маршрут к Telegram: middle / direct.
- Поведение при сбое ME: fallback on/off.
- Внутренняя ME policy: floor mode, no-writer mode, writer-pick mode.

---

## 8) Ограничения и что важно не перепутать

1. **User secret** (`access.users`) и **proxy-secret** (`getProxySecret`) — разные сущности и разные этапы протокола.
2. FakeTLS в Telemt — это не универсальный HTTPS reverse proxy; это маскировочный слой MTProxy.
3. `mask_host/mask_port` используется для camouflage non-MTProxy трафика, а не как основной маршрут к Telegram.
4. Внутренние wire-детали Telegram Middle Proxy протокола в репозитории частично инкапсулированы; надёжнее опираться на названия модулей и runtime-логику, чем приписывать лишние неподтверждённые детали.
