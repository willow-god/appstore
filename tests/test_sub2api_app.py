from pathlib import Path

import yaml
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps" / "sub2api"
VERSION = APP / "0.1.135"


def read_yaml(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def form_field(version_data, env_key: str):
    fields = version_data["additionalProperties"]["formFields"]
    return next(field for field in fields if field.get("envKey") == env_key)


def test_sub2api_app_metadata_is_registered():
    data = read_yaml(APP / "data.yml")

    assert data["name"] == "Sub2API"
    assert data["additionalProperties"]["key"] == "sub2api"
    assert data["additionalProperties"]["name"] == "Sub2API"
    assert data["additionalProperties"]["github"] == "https://github.com/Wei-Shaw/sub2api"
    assert data["additionalProperties"]["document"] == "https://github.com/Wei-Shaw/sub2api#readme"
    assert "API" in data["additionalProperties"]["shortDescEn"]


def test_sub2api_uses_1panel_postgresql_and_redis_fields():
    version_data = read_yaml(VERSION / "data.yml")

    db_type = form_field(version_data, "PANEL_DB_TYPE")
    assert db_type["default"] == "postgresql"
    assert db_type["type"] == "apps"
    assert db_type["child"]["envKey"] == "PANEL_DB_HOST"
    assert db_type["values"] == [{"label": "PostgreSQL", "value": "postgresql"}]

    assert form_field(version_data, "PANEL_DB_NAME")["default"] == "sub2api"
    assert form_field(version_data, "PANEL_DB_USER")["default"] == "sub2api"
    assert form_field(version_data, "PANEL_DB_USER_PASSWORD")["type"] == "password"
    assert form_field(version_data, "PANEL_REDIS_HOST")["type"] == "service"
    assert form_field(version_data, "PANEL_REDIS_HOST")["key"] == "redis"
    assert form_field(version_data, "PANEL_REDIS_ROOT_PASSWORD")["type"] == "password"
    assert form_field(version_data, "REDIS_DB")["default"] == 0


def test_sub2api_port_and_timezone_are_configured_as_requested():
    version_data = read_yaml(VERSION / "data.yml")
    port = form_field(version_data, "PANEL_APP_PORT_HTTP")

    assert port["default"] != 8080
    assert 1 <= port["default"] <= 65535
    assert port["rule"] == "paramPort"

    fields = version_data["additionalProperties"]["formFields"]
    assert all(field.get("envKey") != "TZ" for field in fields)

    compose_text = (VERSION / "docker-compose.yml").read_text(encoding="utf-8")
    compose = yaml.safe_load(compose_text)
    service = compose["services"]["sub2api"]

    assert service["ports"] == ["${PANEL_APP_PORT_HTTP}:8080"]
    assert service["environment"]["TZ"] == "Asia/Shanghai"


def test_sub2api_compose_links_to_1panel_services():
    compose = yaml.safe_load((VERSION / "docker-compose.yml").read_text(encoding="utf-8"))

    assert list(compose["services"].keys()) == ["sub2api"]
    service = compose["services"]["sub2api"]
    env = service["environment"]

    assert service["image"] == "weishaw/sub2api:0.1.135"
    assert env["AUTO_SETUP"] == "true"
    assert env["DATABASE_HOST"] == "${PANEL_DB_HOST}"
    assert env["DATABASE_PORT"] == "${PANEL_DB_PORT}"
    assert env["DATABASE_USER"] == "${PANEL_DB_USER}"
    assert env["DATABASE_PASSWORD"] == "${PANEL_DB_USER_PASSWORD}"
    assert env["DATABASE_DBNAME"] == "${PANEL_DB_NAME}"
    assert env["DATABASE_SSLMODE"] == "disable"
    assert env["REDIS_HOST"] == "${PANEL_REDIS_HOST}"
    assert env["REDIS_PORT"] == "6379"
    assert env["REDIS_PASSWORD"] == "${PANEL_REDIS_ROOT_PASSWORD}"
    assert env["REDIS_DB"] == "${REDIS_DB}"
    assert compose["networks"]["1panel-network"]["external"] is True


def test_sub2api_logo_is_200_square_with_white_background():
    with Image.open(APP / "logo.png") as image:
        assert image.size == (200, 200)
        assert image.mode in {"RGB", "RGBA"}
        rgb = image.convert("RGB")
        corners = [
            rgb.getpixel((0, 0)),
            rgb.getpixel((199, 0)),
            rgb.getpixel((0, 199)),
            rgb.getpixel((199, 199)),
        ]
        assert corners == [(255, 255, 255)] * 4
