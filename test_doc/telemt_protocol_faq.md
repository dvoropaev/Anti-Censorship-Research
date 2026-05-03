# Telemt: протоколы, маршрутизация и Middle Proxy — практический FAQ

> Документ объясняет, как Telemt взаимодействует с клиентами и Telegram-инфраструктурой, зачем нужен Middle-End (ME), когда используется fallback, и как диагностировать поведение маршрутизации.

## 1) Какой протокол используется между пользователем и Telemt?

Коротко: **TCP + MTProxy (MTProto proxy modes)**.

Telemt поддерживает официальные режимы MTProxy:
- **Classic**
- **Secure** (`dd`)
- **Fake TLS** (`ee` + SNI fronting)

Важно по уровню протокола:
- FakeTLS в Telemt — это **режим MTProxy-обфускации**, где handshake имитирует TLS ClientHello/ServerHello для fronting.
- Это не «обычный HTTPS-терминатор», который принимает полноценный TLS-сайт и потом «снимает TLS» для MTProxy: верифицируется MTProxy-совместимый handshake/секрет и дальше идет MTProto proxy data-path.

Ссылка в код/доки:
- [README: поддерживаемые MTProxy режимы](../upstreams/telegram/telemt/README.md)
- [`src/protocol/tls.rs`](../upstreams/telegram/telemt/src/protocol/tls.rs)

## 2) Какой протокол используется между Telemt и Telegram?

Это **другой уровень**, не равный client-facing MTProxy mode. На апстриме выбирается маршрут Telemt.

1. **Direct DC path**
   - Telemt подключается к Telegram DC адресу.
   - Адрес выбирается из `dc_overrides` (если есть) или из статической таблицы DC с учетом IPv4/IPv6-preference.
   - Для нестандартного/неизвестного DC без override используется fallback на `default_dc` (или эффективный fallback к DC2).

2. **Middle-End (ME) path**
   - Telemt использует карту ME endpoint-ов (`proxy_for`) из `getProxyConfig*`.
   - Пул ME управляет writer/reader каналами, покрытием (coverage), floor-политикой, refill/reconnect и admission.

Ссылки:
- [Direct relay: выбор DC и подключение](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- [ME updater: чтение `proxy_for`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)

## 3) С какими серверами Telegram взаимодействует Telemt?

### 3.1 Telegram Core (служебные URL)
При включенном `use_middle_proxy` и в процессе bootstrap/update Telemt использует:
- `https://core.telegram.org/getProxySecret`
- `https://core.telegram.org/getProxyConfig`
- `https://core.telegram.org/getProxyConfigV6`

(или кастомные URL из конфига)

Ключевой момент: это **служебные bootstrap-запросы** (control/bootstrap plane), а не user traffic relay.

Ссылки:
- [`src/transport/middle_proxy/secret.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/secret.rs)
- [`src/maestro/me_startup.rs`](../upstreams/telegram/telemt/src/maestro/me_startup.rs)
- [`src/maestro/helpers.rs` (startup snapshot/cache fallback)](../upstreams/telegram/telemt/src/maestro/helpers.rs)
- [`src/config/types.rs` (поля URL)](../upstreams/telegram/telemt/src/config/types.rs)

### 3.2 Telegram Datacenters (Direct)
- Статические таблицы DC IPv4/IPv6 есть в коде.
- Можно задать `dc_overrides` (по ключу `dc_idx` как строка).
- Для известных DC используется `abs(dc_idx)` в диапазоне таблицы.
- Для неизвестного DC без override — fallback на `default_dc` (валидный диапазон 1..=N), иначе fallback на первый DC таблицы.

Ссылки:
- [`src/protocol/constants.rs`](../upstreams/telegram/telemt/src/protocol/constants.rs)
- [`src/proxy/direct_relay.rs` (`get_dc_addr_static`)](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)

### 3.3 Telegram Middle Proxy endpoints (ME)
- Endpoint-ы приходят из `proxy_for` строк в `getProxyConfig*`.
- Парсятся в карту `dc -> [(ip, port)]`; отдельно может извлекаться `default`.
- Эта карта используется как transport input для ME pool.

Ссылка:
- [`src/transport/middle_proxy/config_updater.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)

## 4) Как Telemt “находит” нужные сервера?

### 4.1 Для direct DC
1. Берет `dc_idx` из handshake-контекста.
2. Выбирает семейство адресов по `network.prefer` + `network.ipv6`.
3. Применяет `dc_overrides` (если есть и парсинг валиден; иначе игнорирует невалидные записи).
4. Если override нет и DC стандартный — берет адрес из статической таблицы.
5. Если DC нестандартный и override нет — fallback на `default_dc` (или на первый DC при невалидном `default_dc`).

### 4.2 Для bootstrap HTTPS-запросов (`getProxy*`, `getProxySecret`, а также другие host:port use-cases)
1. Telemt сначала проверяет `network.dns_overrides` в формате `host:port:ip`.
2. Если override нет — использует обычный DNS (`lookup_host`/system resolution в конкретном месте кода).

Важно: `dns_overrides` не является «глобальной заменой DNS для всех хостов и всех путей», а применяется только в тех кодовых путях, где вызывается resolver override (например, ME HTTPS fetch, mask-host, TLS front fetch, upstream host:port resolution).

Ссылки:
- [`src/proxy/direct_relay.rs` (`get_dc_addr_static`)](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- [`src/transport/middle_proxy/http_fetch.rs` (resolve + DNS)](../upstreams/telegram/telemt/src/transport/middle_proxy/http_fetch.rs)
- [`src/network/dns_overrides.rs`](../upstreams/telegram/telemt/src/network/dns_overrides.rs)

## 5) Что такое ME в Telemt: протокол или policy layer?

В терминах Telemt, ME — это не новый клиентский протокол, а **upstream transport/orchestration слой**:
- endpoint map из `getProxyConfig*`;
- writer/reader pool;
- admission readiness (`admission_ready_conditional_cast`);
- health/refill/reconnect/floor policies;
- route mode cutover для **новых подключений**.

Это control+transport orchestration над relay-путем Telemt → Telegram (через middle endpoints).

Ссылки:
- [Модель ME (RU)](../upstreams/telegram/telemt/docs/Architecture/Model/MODEL.ru.md)
- [`src/maestro/admission.rs`](../upstreams/telegram/telemt/src/maestro/admission.rs)
- [`src/transport/middle_proxy/`](../upstreams/telegram/telemt/src/transport/middle_proxy/)

## 6) Как работает bootstrap/caching/fallback для getProxy* и getProxySecret?

Коротко:
- Для `getProxySecret`: сначала fresh download, при неуспехе — чтение cache/file fallback с проверкой длины.
- Для startup `getProxyConfig*`: сначала fresh snapshot; при пустом/ошибочном результате — попытка disk cache snapshot.
- Если данные недоступны:
  - при `me2dc_fallback=true` ME startup может завершиться fallback-ом в direct режим;
  - при `me2dc_fallback=false` startup продолжает retry-loop.

IPv6 bootstrap:
- `getProxyConfigV6` запрашивается отдельным URL (`proxy_config_v6_url` или default `.../getProxyConfigV6`).
- Реальная пригодность IPv6 пути зависит от network decision/probe и текущих runtime условий.

Ссылки:
- [`src/transport/middle_proxy/secret.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/secret.rs)
- [`src/maestro/helpers.rs` (`load_startup_proxy_config_snapshot`)](../upstreams/telegram/telemt/src/maestro/helpers.rs)
- [`src/maestro/me_startup.rs`](../upstreams/telegram/telemt/src/maestro/me_startup.rs)

## 7) Что именно означает fallback (`me2dc_fallback`, `me2dc_fast`)?

Разделяйте startup и runtime:

1. **Startup fallback**
   - Если ME не может стартовать и `me2dc_fallback=true`, runtime может перейти в direct mode.
   - Если `me2dc_fallback=false`, startup может продолжать ретраи вместо деградации в direct.

2. **Runtime fallback / admission-gate behavior**
   - Решение принимает admission loop по readiness ME pool.
   - `me2dc_fast=true` (при `use_middle_proxy=true` и `me2dc_fallback=true`) разрешает быстрый direct fallback для новых сессий при `not-ready`.
   - Без fast-режима действует grace-логика: отдельные пороги для startup-not-ready и runtime-not-ready перед переводом новых подключений в direct.

3. **Активные сессии при смене route mode**
   - Переключение не означает «мгновенно и прозрачно перенести все активные потоки».
   - В коде есть cutover-механизм поколений; затронутые сессии могут завершаться с route-switch ошибкой (`Session terminated`) после stagger delay.

Ссылки:
- [`src/config/types.rs` (`me2dc_fallback`, `me2dc_fast`)](../upstreams/telegram/telemt/src/config/types.rs)
- [`src/maestro/admission.rs`](../upstreams/telegram/telemt/src/maestro/admission.rs)
- [`src/proxy/route_mode.rs`](../upstreams/telegram/telemt/src/proxy/route_mode.rs)
- [`src/proxy/direct_relay.rs`](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- [`src/proxy/middle_relay.rs`](../upstreams/telegram/telemt/src/proxy/middle_relay.rs)

## 8) Частые уточнения

### 8.1 “ME всегда быстрее direct?”
Не гарантия. В коде и архитектурных материалах это скорее целевая модель/дизайн-намерение (устойчивость, управляемость), а не строгая гарантия latency/throughput для любого сценария.

### 8.2 “Можно ли работать только в direct?”
Да. Если `use_middle_proxy=false`, runtime работает direct-only.

### 8.3 “Что если DNS нестабилен?”
Можно использовать `network.dns_overrides` для конкретных `host:port` маршрутов, где этот механизм реально вызывается.

### 8.4 “Почему вообще нужны `getProxyConfig*`?”
Для актуальной карты ME endpoint-ов (`proxy_for`) и runtime-обновлений map/pool.

### 8.5 “Где смотреть runtime-состояние маршрутизации?”
Практически полезные endpoint-ы API:
- `/v1/runtime/gates` — admission/route/fallback state;
- `/v1/runtime/initialization` — startup/ME init stage;
- `/v1/runtime/me_pool_state` — поколение/контур/рефилл ME pool;
- `/v1/runtime/me_quality` — route drops, coverage-related quality signals;
- `/v1/stats/me-writers`, `/v1/stats/dcs` — writer/DC counters;
- `/v1/runtime/events/recent` — recent control-plane события.

Ссылки:
- [Architecture API](../upstreams/telegram/telemt/docs/Architecture/API/API.md)
- [`src/api/mod.rs` (route matrix)](../upstreams/telegram/telemt/src/api/mod.rs)

## 9) Мини-чеклист диагностики маршрутизации

1. Проверить `use_middle_proxy`.
2. Проверить `me2dc_fallback` и `me2dc_fast`.
3. Проверить startup/runtime readiness (API: `/v1/runtime/gates`, `/v1/runtime/initialization`).
4. Проверить доступность `getProxySecret/getProxyConfig/getProxyConfigV6` и наличие cache snapshot.
5. Проверить `dc_overrides` / `default_dc` и семейство IPv4/IPv6.
6. Проверить `network.dns_overrides` только для релевантных host:port путей.
7. Проверить ME pool state/quality (`/v1/runtime/me_pool_state`, `/v1/runtime/me_quality`, `/v1/stats/me-writers`, `/v1/stats/dcs`).

## 10) Короткий словарь

- **ME (Middle-End)** — upstream transport/orchestration слой через middle proxy endpoints.
- **DC** — Telegram datacenter endpoint для direct-path.
- **Writer** — исходящий канал пула к конкретному ME endpoint.
- **Coverage** — достаточность живых writer-ов по policy.
- **Floor** — минимально целевой уровень writer capacity (static/adaptive policy).
- **Admission gate** — runtime-решение, принимать ли новые подключения и каким route mode.
- **Fallback** — policy-ветка маршрутизации, в том числе для новых подключений при ME not-ready.

## 11) Быстрый индекс ссылок на код

- MTProxy режимы: [README](../upstreams/telegram/telemt/README.md)
- FakeTLS модуль: [`src/protocol/tls.rs`](../upstreams/telegram/telemt/src/protocol/tls.rs)
- Статические DC: [`src/protocol/constants.rs`](../upstreams/telegram/telemt/src/protocol/constants.rs)
- Direct route / `dc_overrides`: [`src/proxy/direct_relay.rs`](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- Bootstrap URL и fallback параметры: [`src/config/types.rs`](../upstreams/telegram/telemt/src/config/types.rs)
- Startup загрузка `getProxyConfig*`: [`src/maestro/me_startup.rs`](../upstreams/telegram/telemt/src/maestro/me_startup.rs)
- Startup cache fallback: [`src/maestro/helpers.rs`](../upstreams/telegram/telemt/src/maestro/helpers.rs)
- Загрузка `getProxySecret`: [`src/transport/middle_proxy/secret.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/secret.rs)
- Парсинг `proxy_for`: [`src/transport/middle_proxy/config_updater.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)
- DNS overrides: [`src/network/dns_overrides.rs`](../upstreams/telegram/telemt/src/network/dns_overrides.rs)
- API route matrix: [`src/api/mod.rs`](../upstreams/telegram/telemt/src/api/mod.rs)

---

Если нужно, в следующей версии можно добавить:
- диаграмму “client -> telemt -> (ME|direct) -> Telegram”;
- таблицу “симптом -> наблюдаемый API сигнал -> проверка policy/конфига -> действие”;
- короткий runbook «startup fallback vs runtime fallback».
