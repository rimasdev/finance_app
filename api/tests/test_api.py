import os
from datetime import datetime
from zoneinfo import ZoneInfo

os.environ["DATABASE_URL"] = "sqlite://"
os.environ["JWT_SECRET"] = "test-secret"

import pytest
from fastapi.testclient import TestClient

from app.db import Base, configure
from app.main import app

configure()


@pytest.fixture
def client():
    Base.metadata.drop_all(configure.__globals__["engine"])
    Base.metadata.create_all(configure.__globals__["engine"])
    with TestClient(app) as test_client:
        yield test_client


def auth(client):
    response = client.post(
        "/auth/register",
        json={"email": "rimas@example.com", "name": "Rimas", "password": "password1"},
    )
    assert response.status_code == 200, response.text
    return response.json()["token"]


def test_register_seeds_categories_and_rejects_duplicate(client):
    token = auth(client)
    categories = client.get("/categories", headers={"Authorization": f"Bearer {token}"})
    names = {row["name"] for row in categories.json()}
    assert "Transport" in names
    assert "Salary" in names
    again = client.post(
        "/auth/register",
        json={"email": "rimas@example.com", "name": "Rimas", "password": "password1"},
    )
    assert again.status_code == 400


def test_sms_updates_balance_and_dedupes(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    created = client.post(
        "/accounts",
        headers=headers,
        json={
            "name": "Flash - Primary",
            "type": "bank",
            "bank_name": "Commercial Bank",
            "last4": "8741",
            "sms_sender": "COMBANK",
            "opening_balance": 10000,
        },
    )
    assert created.status_code == 200, created.text
    today = datetime.now(ZoneInfo("Asia/Colombo")).strftime("%d/%m/%Y")
    body = f"Rs.100.00 debited from A/c XX8741 on {today} 09:15. Info: KEELLS. Avl Bal Rs.9,900.00"
    first = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    assert first.status_code == 200, first.text
    assert first.json()["status"] == "posted"
    assert first.json()["transaction"]["category_name"] == "Shopping"
    assert first.json()["transaction"]["scope"] == "personal"
    second = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    assert second.json()["status"] == "duplicate"
    accounts = client.get("/accounts", headers=headers).json()
    assert accounts[0]["balance"] == 9900
    dash = client.get("/dashboard", headers=headers).json()
    assert dash["spent_today"] == 100


def test_business_account_and_unmatched_sms(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    client.post(
        "/accounts",
        headers=headers,
        json={
            "name": "Studio current",
            "type": "bank",
            "purpose": "business",
            "bank_name": "HNB",
            "last4": "3390",
            "sms_sender": "HNB",
            "opening_balance": 5000,
        },
    )
    posted = client.post(
        "/sms/ingest",
        headers=headers,
        json={
            "body": "LKR 2,000.00 debited from A/c XX3390 on 02/09/2026. Info: DIALOG",
            "sender": "HNB",
        },
    )
    assert posted.json()["status"] == "posted"
    assert posted.json()["transaction"]["scope"] == "business"
    assert posted.json()["transaction"]["category_name"] == "Utilities"
    review = client.post(
        "/sms/ingest",
        headers=headers,
        json={"body": "Rs.50.00 debited from A/c XX1111 on 02/09/2026. Info: CAFE", "manual": True},
    )
    assert review.json()["status"] == "needs_review"
    txn_id = review.json()["transaction"]["id"]
    account_id = client.get("/accounts", headers=headers).json()[0]["id"]
    assigned = client.post(
        f"/transactions/{txn_id}/assign",
        headers=headers,
        json={"account_id": account_id},
    )
    assert assigned.status_code == 200
    assert assigned.json()["scope"] == "business"
    timeline = client.get("/timeline?month=2026-09&scope=business", headers=headers).json()
    assert timeline["expenses"] == 2050


def test_credit_card_opening_balance_is_stored_as_debt(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    created = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Visa", "type": "credit_card", "opening_balance": 1500, "last4": "4242"},
    )
    assert created.json()["balance"] == -1500
    assert created.json()["opening_balance"] == -1500


def test_automations_off_skips_auto_sms(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    created = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Cash", "type": "bank", "last4": "8741", "automations_enabled": False, "opening_balance": 100},
    )
    account_id = created.json()["id"]
    skipped = client.post(
        "/sms/ingest",
        headers=headers,
        json={"body": "Rs.10.00 debited from A/c XX8741 on 02/09/2026. Info: SHOP"},
    )
    assert skipped.json()["status"] == "ignored"
    kept = client.post(
        "/sms/ingest",
        headers=headers,
        json={"body": "Rs.10.00 debited from A/c XX8741 on 02/09/2026. Info: SHOP", "manual": True},
    )
    assert kept.json()["status"] == "posted"
    assert kept.json()["transaction"]["account_id"] == account_id


def test_transfer_is_excluded_from_all_account_income(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    primary = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Primary", "type": "bank", "opening_balance": 1000},
    ).json()
    savings = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Savings", "type": "bank", "opening_balance": 500},
    ).json()
    client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": primary["id"],
            "transfer_account_id": savings["id"],
            "direction": "transfer",
            "amount": 200,
            "merchant": "Move to savings",
            "occurred_at": "2026-09-15T04:00:00",
        },
    )
    client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": primary["id"],
            "direction": "expense",
            "amount": 50,
            "merchant": "Tea",
            "occurred_at": "2026-09-16T04:00:00",
        },
    )
    all_accounts = client.get("/timeline?month=2026-09", headers=headers).json()
    assert all_accounts["expenses"] == 50
    assert all_accounts["income"] == 0
    assert all_accounts["net"] == -50
    one = client.get(f"/timeline?month=2026-09&account_id={primary['id']}", headers=headers).json()
    assert one["expenses"] == 250
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Primary"] == 750
    assert balances["Savings"] == 700


def test_google_and_apple_sign_in(client, monkeypatch):
    monkeypatch.setattr(
        "app.routes.verify_google_id_token",
        lambda token: {"google_id": "g-1", "email": "ada@example.com", "name": "Ada"},
    )
    google = client.post("/auth/google", json={"idToken": "fake"})
    assert google.status_code == 200, google.text
    user_id = google.json()["user"]["id"]
    again = client.post("/auth/google", json={"idToken": "fake"})
    assert again.json()["user"]["id"] == user_id
    password = client.post("/auth/login", json={"email": "ada@example.com", "password": "password1"})
    assert password.status_code == 401

    monkeypatch.setattr(
        "app.routes.verify_apple_id_token",
        lambda token: {"apple_id": "a-1", "email": "ada@example.com", "name": "Ada"},
    )
    apple = client.post(
        "/auth/apple",
        json={"idToken": "fake", "fullName": {"givenName": "Ada", "familyName": "Lovelace"}},
    )
    assert apple.status_code == 200, apple.text
    assert apple.json()["user"]["id"] == user_id
    me = client.get("/me", headers={"Authorization": f"Bearer {apple.json()['token']}"})
    assert me.json()["email"] == "ada@example.com"
