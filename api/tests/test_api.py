import os
from datetime import datetime
from decimal import Decimal
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


def test_sms_purchase_is_categorised(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "last4": "9383", "sms_sender": "COMBANK", "opening_balance": 5000},
    )
    body = "Purchase at Kids Mania Kandy LK for LKR 490.00 on 01/10/26 04:00 PM has been authorised on your debit card ending #9383."
    saved = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    assert saved.status_code == 200, saved.text
    assert saved.json()["transaction"]["category_name"] == "Shopping"


def test_withdrawal_moves_to_cash_when_asked(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 10000, "last4": "9383", "sms_sender": "COMBANK"},
    ).json()
    cash = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Cash", "type": "cash", "opening_balance": 100},
    ).json()
    body = "Withdrawal at PABC LK for LKR 4,000.00 on 01/10/26 04:13 PM from card ending #9383."
    held = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    assert held.json()["transaction"]["direction"] == "expense"
    turned = client.patch(
        "/me",
        headers=headers,
        json={"withdrawal_to_cash": True, "cash_account_id": cash["id"]},
    )
    assert turned.status_code == 200, turned.text
    assert turned.json()["withdrawal_to_cash"] is True
    client.delete(f"/transactions/{held.json()['transaction']['id']}", headers=headers)
    moved = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    txn = moved.json()["transaction"]
    assert txn["direction"] == "transfer"
    assert txn["account_id"] == bank["id"]
    assert txn["transfer_account_id"] == cash["id"]
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Flash"] == 6000
    assert balances["Cash"] == 4100
    manual = client.post(
        "/transactions",
        headers=headers,
        json={"account_id": bank["id"], "direction": "expense", "amount": 490, "merchant": "Kids mania"},
    ).json()
    edited = client.patch(
        f"/transactions/{manual['id']}",
        headers=headers,
        json={"direction": "transfer", "transfer_account_id": cash["id"], "merchant": "Kids mania"},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["direction"] == "transfer"
    assert edited.json()["transfer_account_id"] == cash["id"]


def test_account_can_be_left_out_of_net(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    created = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Cash", "type": "cash", "opening_balance": 200},
    )
    assert created.json()["include_in_net"] is True
    hidden = client.patch(
        f"/accounts/{created.json()['id']}",
        headers=headers,
        json={"include_in_net": False},
    )
    assert hidden.status_code == 200, hidden.text
    assert hidden.json()["include_in_net"] is False
    assert hidden.json()["balance"] == 200


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


def test_loans_between_people_and_own_accounts(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    personal = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Personal", "type": "bank", "purpose": "personal", "opening_balance": 5000},
    ).json()
    business = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Business", "type": "bank", "purpose": "business", "opening_balance": 1000},
    ).json()
    lent = client.post(
        "/loans",
        headers=headers,
        json={
            "kind": "lend",
            "party_kind": "person",
            "party_name": "Kamal",
            "account_id": personal["id"],
            "amount": 800,
            "due_on": "2026-11-01",
        },
    )
    assert lent.status_code == 200, lent.text
    assert lent.json()["remaining"] == 800
    assert lent.json()["party_name"] == "Kamal"
    paid = client.post(
        f"/loans/{lent.json()['id']}/payments",
        headers=headers,
        json={"amount": 300},
    )
    assert paid.status_code == 200, paid.text
    assert paid.json()["remaining"] == 500
    assert paid.json()["settled"] is False
    borrowed = client.post(
        "/loans",
        headers=headers,
        json={
            "kind": "borrow",
            "party_kind": "account",
            "account_id": business["id"],
            "counterparty_account_id": personal["id"],
            "amount": 400,
            "due_on": "2026-12-01",
        },
    )
    assert borrowed.status_code == 200, borrowed.text
    assert borrowed.json()["party_name"] == "Personal"
    same = client.post(
        "/loans",
        headers=headers,
        json={
            "kind": "borrow",
            "party_kind": "account",
            "account_id": business["id"],
            "counterparty_account_id": business["id"],
            "amount": 10,
            "due_on": "2026-12-01",
        },
    )
    assert same.status_code == 400
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Personal"] == 5000 - 800 + 300 - 400
    assert balances["Business"] == 1000 + 400
    timeline = client.get("/timeline?month=2026-10", headers=headers).json()
    assert timeline["expenses"] == 0
    assert timeline["income"] == 0
    earlier = client.post(
        "/loans",
        headers=headers,
        json={
            "kind": "borrow",
            "party_kind": "person",
            "party_name": "Nimal",
            "amount": 250,
            "due_on": "2026-11-15",
        },
    )
    assert earlier.status_code == 200, earlier.text
    assert earlier.json()["account_id"] is None
    assert earlier.json()["remaining"] == 250
    open_ended = client.post(
        "/loans",
        headers=headers,
        json={"kind": "lend", "party_kind": "person", "party_name": "Kamal", "amount": 10},
    )
    assert open_ended.status_code == 200, open_ended.text
    assert open_ended.json()["due_on"] is None
    after = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert after == balances


def test_account_order_and_transfer_without_description(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    first = client.post("/accounts", headers=headers, json={"name": "First", "type": "cash", "opening_balance": 100}).json()
    second = client.post("/accounts", headers=headers, json={"name": "Second", "type": "cash", "opening_balance": 50}).json()
    ordered = client.post("/accounts/order", headers=headers, json={"ids": [second["id"], first["id"]]})
    assert ordered.status_code == 200, ordered.text
    names = [row["name"] for row in client.get("/accounts", headers=headers).json()]
    assert names == ["Second", "First"]
    moved = client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": second["id"],
            "transfer_account_id": first["id"],
            "direction": "transfer",
            "amount": 10,
            "merchant": "",
        },
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["merchant"] == "Transfer"
    spent = client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": second["id"],
            "direction": "expense",
            "amount": 5,
            "merchant": "",
        },
    )
    assert spent.status_code == 200, spent.text
    assert spent.json()["merchant"] == ""


def test_transfer_fee_preferred_account_and_hidden(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    primary = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Primary", "type": "bank", "opening_balance": 1000, "sms_sender": "COMBANK", "bank_name": "Commercial Bank of Sri Lanka"},
    ).json()
    savings = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Savings", "type": "bank", "opening_balance": 500, "sms_sender": "COMBANK", "bank_name": "Commercial Bank of Sri Lanka"},
    ).json()
    preferred = client.patch(f"/accounts/{savings['id']}", headers=headers, json={"preferred": True})
    assert preferred.status_code == 200, preferred.text
    assert preferred.json()["preferred"] is True
    listed = {row["name"]: row["preferred"] for row in client.get("/accounts", headers=headers).json()}
    assert listed == {"Primary": False, "Savings": True}
    preview = client.post(
        "/sms/preview",
        headers=headers,
        json={"body": "Rs. 40.00 debited. Info: SHOP", "sender": "COMBANK"},
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["account_name"] == "Savings"
    moved = client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": primary["id"],
            "transfer_account_id": savings["id"],
            "direction": "transfer",
            "amount": 100,
            "bank_charge": 15,
            "merchant": "",
            "occurred_at": "2026-09-15T04:00:00",
        },
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["bank_charge"] == 15
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Primary"] == 885
    assert balances["Savings"] == 600
    timeline = client.get("/timeline?month=2026-09", headers=headers)
    assert timeline.json()["expenses"] == 15
    hidden = client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": primary["id"],
            "direction": "expense",
            "amount": 20,
            "merchant": "Private",
            "hidden": True,
            "occurred_at": "2026-09-16T04:00:00",
        },
    )
    assert hidden.status_code == 200, hidden.text
    after = client.get("/timeline?month=2026-09", headers=headers).json()
    assert after["expenses"] == 15
    on_account = client.get(f"/timeline?month=2026-09&account_id={primary['id']}", headers=headers).json()
    merchants = [item["merchant"] for day in on_account["days"] for item in day["items"]]
    assert "Private" in merchants


def test_subscription_and_installment(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 5000}).json()
    created = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "Netflix",
            "amount": 1490,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-05",
        },
    )
    assert created.status_code == 200, created.text
    paid = client.post(f"/recurring/{created.json()['id']}/pay", headers=headers)
    assert paid.status_code == 200, paid.text
    assert paid.json()["next_on"] == "2026-11-05"
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Cash"] == 3510
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "installment",
            "name": "Phone",
            "amount": 100,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-01",
            "installments_total": 1,
        },
    )
    assert plan.status_code == 200, plan.text
    done = client.post(f"/recurring/{plan.json()['id']}/pay", headers=headers)
    assert done.json()["active"] is False
    assert done.json()["installments_done"] == 1


def test_installment_keeps_the_shop_and_posts_foreign_amounts_in_rupees(client, monkeypatch):
    monkeypatch.setattr("app.routes._lkr_rate", lambda currency: Decimal("300"))
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 5000}).json()
    created = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "installment",
            "name": "Carnage",
            "provider": "Mint Pay",
            "currency": "USD",
            "amount": 10,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-05",
            "installments_total": 3,
            "note": "fx:Mint Pay|USD",
        },
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["name"] == "Carnage"
    assert body["provider"] == "Mint Pay"
    assert body["currency"] == "USD"
    paid = client.post(f"/recurring/{body['id']}/pay", headers=headers)
    assert paid.status_code == 200, paid.text
    txns = client.get("/transactions", headers=headers).json()
    posted = txns[0]
    assert posted["merchant"] == "Carnage"
    assert posted["amount"] == 3000
    assert posted["note"] == "USD 10.00"


def test_a_dollar_purchase_shows_dollars_and_deducts_rupees(client, monkeypatch):
    monkeypatch.setattr("app.routes._lkr_rate", lambda currency: Decimal("330"))
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 5000, "last4": "8028", "sms_sender": "COMBANK"},
    ).json()
    posted = client.post(
        "/sms/ingest",
        headers=headers,
        json={
            "body": (
                "Dear Cardholder, Purchase at APPLE.COM/BILL SINGAPORE SG for USD 2.99 "
                "on 05/10/26 03:41 AM has been authorised on your debit card ending #8028."
            ),
            "sender": "COMBANK",
        },
    )
    assert posted.status_code == 200, posted.text
    txn = posted.json()["transaction"]
    assert txn["currency"] == "USD"
    assert txn["fx_amount"] == 2.99
    assert txn["amount"] == 986.7
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Flash"] == 4013.3
    edited = client.patch(
        f"/transactions/{txn['id']}",
        headers=headers,
        json={"amount": 1000},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["amount"] == 1000
    assert edited.json()["currency"] == "USD"
    assert edited.json()["fx_amount"] == 2.99


def test_a_recurring_plan_can_be_edited(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 0}).json()
    created = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "Netflix",
            "amount": 1490,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-05",
        },
    )
    assert created.status_code == 200, created.text
    edited = client.patch(
        f"/recurring/{created.json()['id']}",
        headers=headers,
        json={"name": "Spotify", "amount": 749, "currency": "USD"},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["name"] == "Spotify"
    assert edited.json()["amount"] == 749
    assert edited.json()["currency"] == "USD"


def test_a_bank_message_settles_the_matching_plan_once(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 5000, "last4": "3390", "sms_sender": "HNB"},
    ).json()
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "Dialog",
            "amount": 2000,
            "account_id": bank["id"],
            "interval": "monthly",
            "next_on": "2026-09-02",
        },
    )
    assert plan.status_code == 200, plan.text
    posted = client.post(
        "/sms/ingest",
        headers=headers,
        json={"body": "LKR 2,000.00 debited from A/c XX3390 on 02/09/2026. Info: DIALOG", "sender": "HNB"},
    )
    assert posted.status_code == 200, posted.text
    assert posted.json()["status"] == "posted"
    rows = client.get("/recurring", headers=headers).json()
    assert rows[0]["next_on"] == "2026-10-02"
    assert rows[0]["active"] is True
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Flash"] == 3000
    assert len(client.get("/transactions", headers=headers).json()) == 1


def test_recording_the_last_installment_removes_it_and_updates_the_account(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 5000}).json()
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "installment",
            "name": "Carnage",
            "provider": "Mint Pay",
            "amount": 1000,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-04",
            "installments_total": 1,
        },
    ).json()
    paid = client.post(f"/recurring/{plan['id']}/pay", headers=headers)
    assert paid.status_code == 200, paid.text
    assert paid.json()["active"] is False
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Cash"] == 4000


def test_a_manual_expense_settles_the_matching_installment_without_a_second_debit(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 5000}).json()
    client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "installment",
            "name": "Carnage",
            "provider": "Mint Pay",
            "amount": 1000,
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-04",
            "installments_total": 1,
        },
    )
    saved = client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": cash["id"],
            "direction": "expense",
            "amount": 1000,
            "merchant": "Carnage",
            "occurred_at": "2026-10-04T04:00:00",
        },
    )
    assert saved.status_code == 200, saved.text
    rows = client.get("/recurring", headers=headers).json()
    assert rows[0]["active"] is False
    assert len(client.get("/transactions", headers=headers).json()) == 1
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Cash"] == 4000


def test_unmatched_card_can_be_linked_to_an_account(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 5000, "last4": "8741", "sms_sender": "COMBANK"},
    ).json()
    body = "Purchase at Kids Mania Kandy LK for LKR 490.00 on 01/10/26 04:00 PM has been authorised on your debit card ending #9383."
    first = client.post("/sms/ingest", headers=headers, json={"body": body, "sender": "COMBANK"})
    assert first.status_code == 200, first.text
    assert first.json()["status"] == "needs_review"
    assert first.json()["transaction"]["card_last4"] == "9383"
    linked = client.post(f"/accounts/{bank['id']}/cards", headers=headers, json={"last4": "9383"})
    assert linked.status_code == 200, linked.text
    assert "9383" in linked.json()["card_last4s"]
    assert linked.json()["balance"] == 4510
    again = client.post(
        "/sms/ingest",
        headers=headers,
        json={
            "body": "Withdrawal at PABC LK for LKR 100.00 on 01/10/26 05:00 PM from card ending #9383.",
            "sender": "COMBANK",
        },
    )
    assert again.json()["status"] == "posted"
    assert again.json()["transaction"]["account_id"] == bank["id"]


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


def test_category_budget_includes_subcategories(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    account = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Cash", "type": "cash", "opening_balance": 5000},
    ).json()
    groceries = next(row for row in client.get("/categories", headers=headers).json() if row["name"] == "Groceries")
    child = client.post(
        "/categories",
        headers=headers,
        json={"name": "Vegetables", "kind": "expense", "parent_id": groceries["id"], "icon": "groceries"},
    )
    assert child.status_code == 200, child.text
    assert child.json()["parent_id"] == groceries["id"]
    created = client.post(
        "/budgets",
        headers=headers,
        json={"name": "Groceries", "limit_amount": 10000, "category_id": groceries["id"]},
    )
    assert created.status_code == 200, created.text
    again = client.post(
        "/budgets",
        headers=headers,
        json={"name": "Groceries", "limit_amount": 1000, "category_id": groceries["id"]},
    )
    assert again.status_code == 400
    client.post(
        "/transactions",
        headers=headers,
        json={
            "account_id": account["id"],
            "direction": "expense",
            "amount": 250,
            "merchant": "Keells",
            "category_id": child.json()["id"],
        },
    )
    budgets = client.get("/budgets", headers=headers).json()
    groceries_budget = next(row for row in budgets if row["category_id"] == groceries["id"])
    assert groceries_budget["spent"] == 250
    assert groceries_budget["remaining"] == 9750


def test_deleting_a_recorded_payment_brings_the_subscription_back(client):
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    cash = client.post("/accounts", headers=headers, json={"name": "Cash", "type": "cash", "opening_balance": 5000}).json()
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "iCloud+",
            "amount": 2.99,
            "currency": "USD",
            "account_id": cash["id"],
            "interval": "monthly",
            "next_on": "2026-10-04",
        },
    ).json()
    paid = client.post(f"/recurring/{plan['id']}/pay", headers=headers)
    assert paid.status_code == 200, paid.text
    assert paid.json()["next_on"] == "2026-11-04"
    txns = client.get("/transactions", headers=headers).json()
    assert len(txns) == 1
    assert txns[0]["recurring_id"] == plan["id"]
    deleted = client.delete(f"/transactions/{txns[0]['id']}", headers=headers)
    assert deleted.status_code == 200, deleted.text
    rows = client.get("/recurring", headers=headers).json()
    assert rows[0]["next_on"] == "2026-10-04"
    assert rows[0]["active"] is True
    assert client.get("/transactions", headers=headers).json() == []


def test_an_apple_text_settles_icloud_and_deleting_it_brings_the_due_date_back(client, monkeypatch):
    monkeypatch.setattr("app.routes._lkr_rate", lambda currency: Decimal("330"))
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 5000, "last4": "8028", "sms_sender": "COMBANK"},
    ).json()
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "iCloud+",
            "amount": 2.99,
            "currency": "USD",
            "account_id": bank["id"],
            "interval": "monthly",
            "next_on": "2026-10-04",
        },
    ).json()
    posted = client.post(
        "/sms/ingest",
        headers=headers,
        json={
            "body": (
                "Dear Cardholder, Purchase at APPLE.COM/BILL SINGAPORE SG for USD 2.99 "
                "on 05/10/26 03:41 AM has been authorised on your debit card ending #8028."
            ),
            "sender": "COMBANK",
        },
    )
    assert posted.status_code == 200, posted.text
    txn = posted.json()["transaction"]
    assert txn["recurring_id"] == plan["id"]
    rows = client.get("/recurring", headers=headers).json()
    assert rows[0]["next_on"] == "2026-11-04"
    client.delete(f"/transactions/{txn['id']}", headers=headers)
    restored = client.get("/recurring", headers=headers).json()
    assert restored[0]["next_on"] == "2026-10-04"


def test_linking_the_apple_text_counts_as_the_icloud_payment(client, monkeypatch):
    monkeypatch.setattr("app.routes._lkr_rate", lambda currency: Decimal("330"))
    token = auth(client)
    headers = {"Authorization": f"Bearer {token}"}
    bank = client.post(
        "/accounts",
        headers=headers,
        json={"name": "Flash", "type": "bank", "opening_balance": 5000, "last4": "8028", "sms_sender": "COMBANK"},
    ).json()
    posted = client.post(
        "/sms/ingest",
        headers=headers,
        json={
            "body": (
                "Dear Cardholder, Purchase at APPLE.COM/BILL SINGAPORE SG for USD 2.99 "
                "on 05/10/26 03:41 AM has been authorised on your debit card ending #8028."
            ),
            "sender": "COMBANK",
        },
    ).json()["transaction"]
    plan = client.post(
        "/recurring",
        headers=headers,
        json={
            "kind": "subscription",
            "name": "iCloud+",
            "amount": 2.99,
            "currency": "USD",
            "account_id": bank["id"],
            "interval": "monthly",
            "next_on": "2026-10-04",
        },
    ).json()
    linked = client.post(f"/transactions/{posted['id']}/recurring", headers=headers, json={"recurring_id": plan["id"]})
    assert linked.status_code == 200, linked.text
    assert linked.json()["recurring_id"] == plan["id"]
    rows = client.get("/recurring", headers=headers).json()
    assert rows[0]["next_on"] == "2026-11-04"
    balances = {row["name"]: row["balance"] for row in client.get("/accounts", headers=headers).json()}
    assert balances["Flash"] == 4013.3
    assert len(client.get("/transactions", headers=headers).json()) == 1
