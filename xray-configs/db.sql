CREATE DATABASE vpn_time;

\c vpn_time;

CREATE TABLE sources (
    id SERIAL PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    description TEXT DEFAULT NULL
);

-- Таблица пользователей
CREATE TABLE users (
    telegram_id BIGINT PRIMARY KEY,  -- Уникальный идентификатор пользователя в Telegram
    name VARCHAR(100) NOT NULL,      -- Имя (логин) пользователя в telegram (которое через @)
    email VARCHAR(100) DEFAULT NULL,
    free_time INT DEFAULT 0,         -- Оставшееся бесплатное время (в минутах)
    paid_time INT DEFAULT 0,         -- Оставшееся Платное время (в минутах)
    used_time INT DEFAULT 0,         -- Израсходованное время (в минутах)
    invited_by BIGINT REFERENCES users(telegram_id) ON DELETE SET NULL, -- Кто пригласил (Telegram ID)
    tariff INT DEFAULT 1,            -- Тариф пользователя; 1-9 пользовательские тарифы; 11-19 системные тарифы
    first_pay DATE DEFAULT NULL,     -- Дата первой оплаты
    registered_at DATE DEFAULT CURRENT_DATE, -- Дата регистрации пользователя
    last_active_at DATE DEFAULT NULL, -- Дата последней активности
    low_balance_notification TIMESTAMP DEFAULT NULL, -- Дата, часы, минуты уведомления о низком балансе
    zero_balance_notification TIMESTAMP DEFAULT NULL, -- Дата, часы, минуты уведомления о нулевом балансе
    is_blocked BOOLEAN DEFAULT FALSE, -- Заблокирован или нет (TRUE/FALSE)
    referral_code VARCHAR(50) NOT NULL UNIQUE,    -- Реферальный промокод для приглашения других пользователей
    source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL,
    source_raw TEXT DEFAULT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'new'
        CHECK (status IN (
           'new',
           'lost_new',
           'potencial',
           'lost_potencial',
           'active',
           'lost_active',
           'lost',
           'untracked'
       ))
);

-- Таблица типов кластеров Xray
CREATE TABLE xray_cluster_types (
    name VARCHAR(100) PRIMARY KEY,      -- Уникальное имя типа кластера
    description VARCHAR(256) NOT NULL,  -- Описание типа кластера
    is_active BOOLEAN DEFAULT TRUE      -- Флаг активности (TRUE - включен, FALSE - выключен)
);

-- Таблица кластеров Xray
CREATE TABLE xray_clusters (
    id SERIAL PRIMARY KEY,                       -- Уникальный идентификатор кластера Xray
    cluster_type VARCHAR(100) NOT NULL REFERENCES xray_cluster_types(name) ON DELETE RESTRICT, -- Тип кластера Xray
    location VARCHAR(100) NOT NULL               -- Локация кластера
);

-- Таблица серверов Xray
CREATE TABLE xray_servers (
    id SERIAL PRIMARY KEY,                 -- Уникальный идентификатор сервера Xray
    cluster_id INT NOT NULL REFERENCES xray_clusters(id) ON DELETE CASCADE, -- Кластер Xray
    address VARCHAR(255) NOT NULL,         -- Адрес сервера (URL или IP)
    name VARCHAR(100) NOT NULL             -- Имя сервера
);

-- Таблица ключей Xray
CREATE TABLE xray_keys (
    id SERIAL PRIMARY KEY,                       -- Уникальный идентификатор ключа Xray
    name VARCHAR(128) NOT NULL,
    user_id BIGINT NOT NULL
        REFERENCES users(telegram_id)
        ON DELETE CASCADE,
    key VARCHAR(16) NOT NULL UNIQUE,             -- Уникальный hex-ключ длиной 16 символов
    uuid UUID NOT NULL,                          -- UUID клиента
    CONSTRAINT xray_keys_key_hex CHECK (key ~ '^[0-9a-fA-F]{16}$') -- Проверка формата hex-ключа
);


-- Автозаполнение
INSERT INTO xray_cluster_types (name, description)
VALUES ('vtt', 'VLESS-TCP-TLS');
