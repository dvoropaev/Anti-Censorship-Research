# Telemt: протоколы, маршрутизация и Middle Proxy — практический FAQ

> Документ объясняет, как Telemt взаимодействует с клиентами и Telegram-инфраструктурой, зачем нужен Middle-End (ME), когда используется fallback, и как диагностировать поведение маршрутизации.

## 1) Какой протокол используется между пользователем и Telemt?

Коротко: **TCP + MTProxy (MTProto proxy modes)**.

Telemt поддерживает официальные режимы MTProxy:
- **Classic**
- **Secure** (`dd`)
- **Fake TLS** (`ee` + SNI fronting)

Ссылка в код/доки:
- [README: поддерживаемые MTProxy режимы](../upstreams/telegram/telemt/README.md)

Пример из кода (док-комментарий FakeTLS):

```rust
//! This module handles the fake TLS 1.3 handshake used by MTProto proxy
//! for domain fronting. The handshake looks like valid TLS 1.3 but
//! actually carries MTProto authentication data.
```

Источник:
- [`src/protocol/tls.rs`](../upstreams/telegram/telemt/src/protocol/tls.rs)

## 2) Какой протокол используется между Telemt и Telegram?

Зависит от выбранного транспортного режима:

1. **Direct DC path**
   - Telemt подключается к Telegram DC (обычно порт 443)
   - выполняет TG/MTProto proxy handshake
   - после этого идет обычный relay зашифрованного трафика

2. **Middle-End (ME) path**
   - Telemt использует Middle Proxy endpoints (карта `proxy_for`)
   - поддерживает пул writer/reader каналов
   - динамически обновляет карту endpoint-ов через `getProxyConfig`/`getProxyConfigV6`

Ссылки:
- [Direct relay: выбор DC и подключение](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- [ME updater: чтение `proxy_for`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)

## 3) С какими серверами Telegram взаимодействует Telemt?

### 3.1 Telegram Core (служебные URL)
Telemt может запрашивать:
- `https://core.telegram.org/getProxySecret`
- `https://core.telegram.org/getProxyConfig`
- `https://core.telegram.org/getProxyConfigV6`

(или кастомные URL из конфига)

Пример из кода:

```rust
proxy_secret_url.unwrap_or("https://core.telegram.org/getProxySecret")
```

```rust
.proxy_config_v4_url
.as_deref()
.unwrap_or("https://core.telegram.org/getProxyConfig")
```

```rust
.proxy_config_v6_url
.as_deref()
.unwrap_or("https://core.telegram.org/getProxyConfigV6")
```

Ссылки:
- [`src/transport/middle_proxy/secret.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/secret.rs)
- [`src/maestro/me_startup.rs`](../upstreams/telegram/telemt/src/maestro/me_startup.rs)
- [`src/config/types.rs` (поля URL)](../upstreams/telegram/telemt/src/config/types.rs)

### 3.2 Telegram Datacenters (Direct)
- Статические таблицы DC IPv4/IPv6 есть в коде.
- Также можно задать `dc_overrides` в конфиге.

Пример из кода (статические DC):

```rust
pub const TG_DATACENTER_PORT: u16 = 443;
pub static TG_DATACENTERS_V4: LazyLock<Vec<IpAddr>> = LazyLock::new(|| { ... });
pub static TG_DATACENTERS_V6: LazyLock<Vec<IpAddr>> = LazyLock::new(|| { ... });
```

Ссылки:
- [`src/protocol/constants.rs`](../upstreams/telegram/telemt/src/protocol/constants.rs)
- [`src/proxy/direct_relay.rs` (`dc_overrides` + fallback)](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)

### 3.3 Telegram Middle Proxy endpoints (ME)
- Endpoint-ы приходят из `proxy_for` строк в `getProxyConfig*`.
- Эти endpoint-ы и составляют рабочую карту маршрутизации для ME пула.

Пример из кода:

```rust
// proxy_for 4 91.108.4.195:8888;
// proxy_for 2 [2001:67c:04e8:f002::d]:80;
fn parse_proxy_line(line: &str) -> Option<(i32, IpAddr, u16)> { ... }
```

Ссылка:
- [`src/transport/middle_proxy/config_updater.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)

## 4) Как Telemt “находит” нужные сервера?

Основной порядок:

1. Берет целевой `dc_idx` из handshake-контекста.
2. Проверяет `dc_overrides` (если есть).
3. Если override нет — использует статическую таблицу DC.
4. Если запрошен нестандартный DC — применяет fallback на `default_dc`.
5. Для ME-режима периодически обновляет endpoint-карту из `getProxyConfig*`.
6. Для хостов учитывает `network.dns_overrides`, затем обычный DNS.

Пример из кода (сначала override, затем DNS):

```rust
if let Some(addr) = resolve_socket_addr(host, port) {
    return Ok(addr);
}
let addrs = tokio::net::lookup_host((host, port)).await?;
```

Ссылки:
- [`src/proxy/direct_relay.rs` (`get_dc_addr_static`)](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- [`src/transport/middle_proxy/http_fetch.rs` (resolve + DNS)](../upstreams/telegram/telemt/src/transport/middle_proxy/http_fetch.rs)

## 5) Зачем Telemt ходит к Telegram Middle Proxy, если можно напрямую?

Потому что ME — это **управляемый транспортный слой**, который обычно лучше в эксплуатационном смысле:

- более стабильная пропускная способность и предсказуемая latency;
- снижение churn и reconnect-штормов за счет adaptive policy;
- изоляция деградации (проблема одной сессии/канала не должна ломать весь поток);
- более гибкое восстановление покрытия (refill/reconnect), чем “просто прямой коннект”.

Direct остается важным режимом, но в архитектуре Telemt ME задуман как основной путь в типичных условиях.

Ссылки:
- [Модель ME (RU)](../upstreams/telegram/telemt/docs/Architecture/Model/MODEL.ru.md)
- [`README.md` (позиционирование Middle-End)](../upstreams/telegram/telemt/README.md)

## 6) Что значит “как fallback”?

**Fallback** = резервный маршрут (**план Б**), когда основной путь не готов/временно недоступен.

Пример:
- основной путь: `ME`
- fallback: `direct DC`

Если включен `me2dc_fallback`, Telemt может переключиться на direct path, когда ME не инициализировался или потерял готовность по policy.

Пример из кода:

```rust
/// Allow fallback from Middle-End mode to direct DC when ME startup cannot be initialized.
pub me2dc_fallback: bool,
```

Ссылка:
- [`src/config/types.rs` (`me2dc_fallback`, `me2dc_fast`)](../upstreams/telegram/telemt/src/config/types.rs)

## 7) Когда именно может сработать fallback?

Типовые случаи:
- не удалось получить/валидировать bootstrap-данные ME (secret/config);
- недостаточное покрытие ME пула для policy admission;
- runtime-деградация по DC/endpoint (в зависимости от policy и настроек).

Важно: в модели Telemt fallback — это **ожидаемая policy-ветка**, а не автоматический признак бага.

Ссылка:
- [MODEL.ru.md (про fallback policy)](../upstreams/telegram/telemt/docs/Architecture/Model/MODEL.ru.md)

## 8) Частые уточнения

### 8.1 “ME всегда быстрее direct?”
Не всегда в каждом микросценарии, но архитектурно Telemt оптимизирует ME под **стабильность + предсказуемость** в реальной нагрузке.

### 8.2 “Можно ли работать только в direct?”
Да, это возможно настройками. Но теряются преимущества ME orchestration (пул, адаптивные политики, устойчивость на деградациях).

### 8.3 “Что если DNS нестабилен?”
Используются `dns_overrides`, что позволяет жестко зафиксировать разрешение конкретных host:port.

### 8.4 “Почему вообще нужны `getProxyConfig*`?”
Чтобы получать актуальную карту Middle Proxy endpoint-ов (а не жить только на статике).

### 8.5 “Где смотреть runtime-состояние маршрутизации?”
Смотреть runtime API и состояние ME pool, counters, coverage/floor.

Ссылка:
- [Architecture API](../upstreams/telegram/telemt/docs/Architecture/API/API.md)

## 9) Мини-чеклист диагностики маршрутизации

1. Проверить, включен ли `use_middle_proxy`.
2. Проверить `me2dc_fallback` и `me2dc_fast`.
3. Проверить доступность `getProxySecret/getProxyConfig/getProxyConfigV6`.
4. Проверить `dc_overrides` / `default_dc`.
5. Проверить DNS и `network.dns_overrides`.
6. Сопоставить runtime-состояние с policy (coverage/floor/admission).

## 10) Короткий словарь

- **ME (Middle-End)** — режим работы через middle proxy endpoints.
- **DC** — Telegram datacenter endpoint.
- **Writer** — долгоживущий исходящий канал к конкретному ME endpoint.
- **Coverage** — достаточное число живых writer-ов для приема трафика.
- **Floor** — целевая минимальная емкость writer-ов.
- **Churn** — частые reconnect/remove циклы.
- **Fallback** — резервный маршрут при недоступности основного.

## 11) Быстрый индекс ссылок на код

- MTProxy режимы: [README](../upstreams/telegram/telemt/README.md)
- FakeTLS модуль: [`src/protocol/tls.rs`](../upstreams/telegram/telemt/src/protocol/tls.rs)
- Статические DC: [`src/protocol/constants.rs`](../upstreams/telegram/telemt/src/protocol/constants.rs)
- Direct route / `dc_overrides`: [`src/proxy/direct_relay.rs`](../upstreams/telegram/telemt/src/proxy/direct_relay.rs)
- Bootstrap URL и fallback параметры: [`src/config/types.rs`](../upstreams/telegram/telemt/src/config/types.rs)
- Startup загрузка `getProxyConfig*`: [`src/maestro/me_startup.rs`](../upstreams/telegram/telemt/src/maestro/me_startup.rs)
- Загрузка `getProxySecret`: [`src/transport/middle_proxy/secret.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/secret.rs)
- Парсинг `proxy_for`: [`src/transport/middle_proxy/config_updater.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/config_updater.rs)
- DNS + overrides: [`src/transport/middle_proxy/http_fetch.rs`](../upstreams/telegram/telemt/src/transport/middle_proxy/http_fetch.rs)

---

Если нужно, в следующей версии можно добавить:
- диаграмму “client -> telemt -> (ME|direct) -> Telegram”;
- таблицу “сигнал/симптом -> вероятная причина -> действие”;
- шаблон runbook для on-call.
