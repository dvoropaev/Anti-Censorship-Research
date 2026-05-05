#!/usr/bin/env python3
import base64
import configparser
import logging
import os
from dataclasses import dataclass
from typing import List, Optional, Tuple

import psycopg2
from flask import Flask, Response, abort

DEFAULT_CONFIG_PATH = "/etc/vpn-time/sub-gen/config.ini"


@dataclass
class AppConfig:
    db_host: str
    db_port: int
    db_user: str
    db_password: str
    db_name: str
    listen_host: str
    listen_port: int
    log_file: str


def load_config(path: str) -> AppConfig:
    config = configparser.ConfigParser()
    if not config.read(path):
        raise RuntimeError(f"Не удалось прочитать конфигурацию: {path}")

    return AppConfig(
        db_host=config["PostgreSQL"]["Address"],
        db_port=config.getint("PostgreSQL", "Port"),
        db_user=config["PostgreSQL"]["User"],
        db_password=config["PostgreSQL"]["Password"],
        db_name=config["PostgreSQL"].get("Database", "vpn_time"),
        listen_host=config["Service"].get("Host", "127.0.0.1"),
        listen_port=config["Service"].getint("Port", 8085),
        log_file=config["Service"].get("LogFile", "/var/vpn-time/log/sub-gen.log"),
    )


def setup_logging(log_file: str) -> None:
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    logging.basicConfig(
        filename=log_file,
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )


def get_db_connection(app_config: AppConfig) -> psycopg2.extensions.connection:
    return psycopg2.connect(
        host=app_config.db_host,
        port=app_config.db_port,
        user=app_config.db_user,
        password=app_config.db_password,
        database=app_config.db_name,
    )


def fetch_active_key(conn: psycopg2.extensions.connection, key_value: str) -> Optional[Tuple[str, str]]:
    query = (
        "SELECT xray_keys.uuid, xray_keys.name "
        "FROM xray_keys "
        "JOIN users ON users.telegram_id = xray_keys.user_id "
        "WHERE xray_keys.key = %s AND (users.free_time + users.paid_time) > 0"
    )
    with conn.cursor() as cur:
        cur.execute(query, (key_value,))
        return cur.fetchone()


def fetch_clusters(conn: psycopg2.extensions.connection) -> List[Tuple[int, str, str]]:
    query = (
        "SELECT xc.id, xc.cluster_type, xc.location "
        "FROM xray_clusters xc "
        "JOIN xray_cluster_types xct ON xct.name = xc.cluster_type "
        "WHERE xct.is_active = TRUE"
    )
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def pick_cluster_server(conn: psycopg2.extensions.connection, cluster_id: int) -> Optional[str]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT address FROM xray_servers WHERE cluster_id = %s ORDER BY RANDOM() LIMIT 1",
            (cluster_id,),
        )
        row = cur.fetchone()
    return row[0] if row else None


def build_vtt_url(uuid_value: str, address: str, location: str, cluster_type: str, key_name: str) -> str:
    label = f"{location}-{cluster_type}-{key_name}"
    return (
        f"vless://{uuid_value}@{address}:443"
        f"?type=tcp&security=tls&encryption=none&alpn=http%2F1.1&sni={address}"
        f"#{label}"
    )


def build_subscription_data(
    conn: psycopg2.extensions.connection,
    uuid_value: str,
    key_name: str,
) -> List[str]:
    urls: List[str] = []
    clusters = fetch_clusters(conn)
    for cluster_id, cluster_type, location in clusters:
        address = pick_cluster_server(conn, cluster_id)
        if not address:
            logging.warning("Не найден сервер для кластера %s", cluster_id)
            continue
        if cluster_type == "vtt":
            urls.append(build_vtt_url(str(uuid_value), address, location, cluster_type, key_name))
        else:
            logging.warning("Неизвестный тип кластера: %s", cluster_type)
    return urls


def encode_subscription(urls: List[str]) -> str:
    raw = "\n".join(urls)
    return base64.b64encode(raw.encode("utf-8")).decode("utf-8")


def create_app(config_path: str = DEFAULT_CONFIG_PATH) -> Flask:
    app = Flask(__name__)
    app_config = load_config(config_path)
    setup_logging(app_config.log_file)
    app.config["APP_CONFIG"] = app_config

    @app.route("/health")
    def health() -> Response:
        return Response("ok", mimetype="text/plain")

    @app.route("/getsub/xray/<key_value>")
    def get_subscription(key_value: str) -> Response:
        conf: AppConfig = app.config["APP_CONFIG"]
        try:
            with get_db_connection(conf) as conn:
                key_data = fetch_active_key(conn, key_value)
                if not key_data:
                    abort(404)
                uuid_value, key_name = key_data
                urls = build_subscription_data(conn, uuid_value, key_name)
        except Exception:
            logging.exception("Ошибка генерации подписки для ключа %s", key_value)
            abort(500)

        encoded_subscription = encode_subscription(urls)
        headers = {"Content-Disposition": f'attachment; filename="{key_value}.txt"'}
        return Response(encoded_subscription, mimetype="text/plain", headers=headers)

    return app


app = create_app(os.getenv("SUBGEN_CONFIG", DEFAULT_CONFIG_PATH))


if __name__ == "__main__":
    cfg: AppConfig = app.config["APP_CONFIG"]
    app.run(host=cfg.listen_host, port=cfg.listen_port)
