import csv
import io
import re
from datetime import date, datetime, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import decode_token, hash_password, make_token, verify_password
from app.db import get_db
from app.models import Account, Budget, Category, Loan, LoanPayment, Recurring, Transaction, User, utcnow
from app.oauth import OAuthError, verify_apple_id_token, verify_google_id_token
from app.sms_parser import parse_sms
from app.services import (
    account_json,
    account_map,
    budget_rows,
    category_map,
    dashboard,
    ingest_sms,
    insights,
    apply_withdrawal_transfer,
    match_account,
    remember_card,
    loan_json,
    seed_categories,
    timeline,
    txn_json,
    user_json,
)

router = APIRouter()
bearer = HTTPBearer(auto_error=False)

ACCOUNT_TYPES = {"cash", "bank", "credit_card", "debit_card"}
PURPOSES = {"personal", "business"}
DIRECTIONS = {"expense", "income", "transfer"}


class RegisterIn(BaseModel):
    email: str
    name: str
    password: str

    @field_validator("email")
    @classmethod
    def clean_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value):
            raise ValueError("Enter a valid email")
        return value

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 2:
            raise ValueError("Name is too short")
        return value

    @field_validator("password")
    @classmethod
    def clean_password(cls, value: str) -> str:
        if len(value) < 8:
            raise ValueError("Password must be at least 8 characters")
        return value


class LoginIn(BaseModel):
    email: str
    password: str


class GoogleIn(BaseModel):
    idToken: str


class AppleName(BaseModel):
    givenName: str | None = None
    familyName: str | None = None


class AppleIn(BaseModel):
    idToken: str
    fullName: AppleName | None = None


class MePatch(BaseModel):
    name: str | None = None
    month_start_day: int | None = Field(default=None, ge=1, le=28)
    timezone: str | None = None
    withdrawal_to_cash: bool | None = None
    cash_account_id: str | None = None


class AccountIn(BaseModel):
    name: str
    type: str
    purpose: str = "personal"
    bank_name: str = ""
    last4: str = ""
    sms_sender: str = ""
    opening_balance: Decimal = Decimal("0")
    automations_enabled: bool = True
    include_in_net: bool = True

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Account name is required")
        return value

    @field_validator("type")
    @classmethod
    def clean_type(cls, value: str) -> str:
        if value not in ACCOUNT_TYPES:
            raise ValueError("Unknown account type")
        return value

    @field_validator("purpose")
    @classmethod
    def clean_purpose(cls, value: str) -> str:
        if value not in PURPOSES:
            raise ValueError("Unknown account purpose")
        return value

    @field_validator("last4")
    @classmethod
    def clean_last4(cls, value: str) -> str:
        digits = re.sub(r"\D", "", value or "")
        if not digits:
            return ""
        if len(digits) < 4:
            raise ValueError("Enter the last 4 digits")
        return digits[-4:]


class AccountPatch(BaseModel):
    name: str | None = None
    type: str | None = None
    purpose: str | None = None
    bank_name: str | None = None
    last4: str | None = None
    sms_sender: str | None = None
    opening_balance: Decimal | None = None
    automations_enabled: bool | None = None
    preferred: bool | None = None
    include_in_net: bool | None = None
    archived: bool | None = None


class CategoryIn(BaseModel):
    name: str
    kind: str
    icon: str = "other"
    color: str = "#9CA3AF"
    parent_id: str | None = None

    @field_validator("kind")
    @classmethod
    def clean_kind(cls, value: str) -> str:
        if value not in {"expense", "income"}:
            raise ValueError("Kind must be expense or income")
        return value

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Category name is required")
        return value


def _clean_tags(value: str) -> str:
    parts: list[str] = []
    for raw in value.split(","):
        tag = " ".join(raw.split())
        if not tag:
            continue
        parts.append(tag[:24])
        if len(parts) == 8:
            break
    return ", ".join(parts)


class TxnIn(BaseModel):
    account_id: str
    direction: str
    amount: Decimal = Field(gt=0)
    bank_charge: Decimal = Field(default=Decimal("0"), ge=0)
    merchant: str = ""
    hidden: bool = False
    category_id: str | None = None
    transfer_account_id: str | None = None
    occurred_at: datetime | None = None
    note: str = ""
    tags: str = ""
    scope: str | None = None

    @field_validator("direction")
    @classmethod
    def clean_direction(cls, value: str) -> str:
        if value not in DIRECTIONS:
            raise ValueError("Unknown direction")
        return value

    @field_validator("merchant")
    @classmethod
    def clean_merchant(cls, value: str) -> str:
        return value.strip()


class TxnPatch(BaseModel):
    account_id: str | None = None
    transfer_account_id: str | None = None
    category_id: str | None = None
    direction: str | None = None
    merchant: str | None = None
    note: str | None = None
    tags: str | None = None
    scope: str | None = None
    amount: Decimal | None = Field(default=None, gt=0)
    bank_charge: Decimal | None = Field(default=None, ge=0)
    hidden: bool | None = None
    occurred_at: datetime | None = None


class AssignIn(BaseModel):
    account_id: str
    category_id: str | None = None


class LoanIn(BaseModel):
    kind: str
    party_kind: str
    party_name: str = ""
    counterparty_account_id: str | None = None
    account_id: str | None = None
    amount: Decimal = Field(gt=0)
    due_on: date | None = None
    note: str = ""

    @field_validator("kind")
    @classmethod
    def clean_kind(cls, value: str) -> str:
        if value not in {"lend", "borrow"}:
            raise ValueError("Choose lend or borrow")
        return value

    @field_validator("party_kind")
    @classmethod
    def clean_party(cls, value: str) -> str:
        if value not in {"person", "business", "account"}:
            raise ValueError("Choose a person, a business, or one of your accounts")
        return value

    @field_validator("account_id")
    @classmethod
    def blank_account(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        return value


class LoanPaymentIn(BaseModel):
    amount: Decimal = Field(gt=0)
    account_id: str | None = None
    occurred_at: datetime | None = None


class BudgetIn(BaseModel):
    name: str
    limit_amount: Decimal = Field(gt=0)
    category_id: str | None = None
    account_id: str | None = None

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Budget name is required")
        return value


class SmsIn(BaseModel):
    body: str
    sender: str = ""
    received_at: datetime | None = None
    manual: bool = False


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise HTTPException(401, "Missing token")
    try:
        user_id = decode_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(401, "Invalid token") from exc
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(401, "Invalid token")
    return user


def _owned_account(db: Session, user: User, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None or account.user_id != user.id:
        raise HTTPException(404, "Account not found")
    return account


def _owned_category(db: Session, user: User, category_id: str | None) -> Category | None:
    if not category_id:
        return None
    category = db.get(Category, category_id)
    if category is None or category.user_id != user.id:
        raise HTTPException(404, "Category not found")
    return category


@router.post("/auth/register")
def register(body: RegisterIn, db: Session = Depends(get_db)):
    if db.query(User).filter_by(email=body.email).first():
        raise HTTPException(400, "An account with that email already exists")
    user = User(email=body.email, name=body.name, password_hash=hash_password(body.password))
    db.add(user)
    db.flush()
    seed_categories(db, user.id)
    db.commit()
    db.refresh(user)
    return {"token": make_token(user.id), "user": user_json(user)}


@router.post("/auth/login")
def login(body: LoginIn, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    user = db.query(User).filter_by(email=email).first()
    if user is None or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Email or password is wrong")
    return {"token": make_token(user.id), "user": user_json(user)}


def _session(user: User) -> dict:
    return {"token": make_token(user.id), "user": user_json(user)}


def _new_social_user(db: Session, *, email: str, name: str, provider: str, google_id: str | None = None, apple_id: str | None = None) -> User:
    user = User(
        email=email,
        name=name[:120] or email.split("@")[0],
        provider=provider,
        google_id=google_id,
        apple_id=apple_id,
    )
    db.add(user)
    db.flush()
    seed_categories(db, user.id)
    db.commit()
    db.refresh(user)
    return user


@router.post("/auth/google")
def google_login(body: GoogleIn, db: Session = Depends(get_db)):
    try:
        google = verify_google_id_token(body.idToken)
    except OAuthError as exc:
        raise HTTPException(exc.status, exc.message) from exc
    user = (
        db.query(User)
        .filter((User.google_id == google["google_id"]) | (User.email == google["email"]))
        .first()
    )
    if user is None:
        user = _new_social_user(
            db,
            email=google["email"],
            name=google["name"],
            provider="google",
            google_id=google["google_id"],
        )
    elif not user.google_id:
        user.google_id = google["google_id"]
        db.commit()
        db.refresh(user)
    return _session(user)


@router.post("/auth/apple")
def apple_login(body: AppleIn, db: Session = Depends(get_db)):
    try:
        apple = verify_apple_id_token(body.idToken)
    except OAuthError as exc:
        raise HTTPException(exc.status, exc.message) from exc
    user = (
        db.query(User)
        .filter((User.apple_id == apple["apple_id"]) | (User.email == apple["email"]))
        .first()
    )
    given = body.fullName.givenName if body.fullName else None
    family = body.fullName.familyName if body.fullName else None
    full_name = " ".join(part.strip() for part in (given, family) if part and part.strip())
    if user is None:
        user = _new_social_user(
            db,
            email=apple["email"],
            name=full_name or apple["name"],
            provider="apple",
            apple_id=apple["apple_id"],
        )
    elif not user.apple_id:
        user.apple_id = apple["apple_id"]
        if full_name and user.name in {"Apple User", user.email.split("@")[0]}:
            user.name = full_name[:120]
        db.commit()
        db.refresh(user)
    return _session(user)


@router.get("/me")
def me(user: User = Depends(current_user)):
    return user_json(user)


@router.patch("/me")
def patch_me(body: MePatch, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if body.name is not None:
        name = body.name.strip()
        if len(name) < 2:
            raise HTTPException(400, "Name is too short")
        user.name = name
    if body.month_start_day is not None:
        user.month_start_day = body.month_start_day
    if body.timezone is not None and body.timezone.strip():
        user.timezone = body.timezone.strip()
    if body.withdrawal_to_cash is not None:
        user.withdrawal_to_cash = body.withdrawal_to_cash
    if body.cash_account_id is not None:
        if body.cash_account_id == "":
            user.cash_account_id = None
        else:
            cash = _owned_account(db, user, body.cash_account_id)
            if cash.type != "cash":
                raise HTTPException(400, "Pick a cash account")
            user.cash_account_id = cash.id
    db.commit()
    db.refresh(user)
    return user_json(user)


@router.delete("/me")
def delete_me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.query(Budget).filter_by(user_id=user.id).delete()
    db.query(Recurring).filter_by(user_id=user.id).delete()
    db.query(Transaction).filter_by(user_id=user.id).delete()
    db.query(Category).filter_by(user_id=user.id).delete()
    db.query(Account).filter_by(user_id=user.id).delete()
    db.delete(user)
    db.commit()
    return {"ok": True}


@router.get("/accounts")
def list_accounts(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(Account)
        .filter_by(user_id=user.id, archived=False)
        .order_by(Account.sort_order, Account.created_at)
        .all()
    )
    return [account_json(db, row) for row in rows]


class AccountOrderIn(BaseModel):
    ids: list[str]


@router.post("/accounts/order")
def order_accounts(body: AccountOrderIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.query(Account).filter_by(user_id=user.id, archived=False).all()
    known = {row.id: row for row in rows}
    if set(body.ids) != set(known):
        raise HTTPException(400, "Include every account")
    for index, account_id in enumerate(body.ids):
        known[account_id].sort_order = index
    db.commit()
    ordered = (
        db.query(Account)
        .filter_by(user_id=user.id, archived=False)
        .order_by(Account.sort_order, Account.created_at)
        .all()
    )
    return [account_json(db, row) for row in ordered]


@router.post("/accounts")
def create_account(body: AccountIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    opening = body.opening_balance
    if body.type == "credit_card" and opening > 0:
        opening = -opening
    last = (
        db.query(func.max(Account.sort_order)).filter(Account.user_id == user.id).scalar()
    )
    account = Account(
        user_id=user.id,
        name=body.name,
        sort_order=int(last or 0) + 1,
        type=body.type,
        purpose=body.purpose,
        bank_name=body.bank_name.strip(),
        last4=body.last4,
        sms_sender=body.sms_sender.strip(),
        opening_balance=opening,
        automations_enabled=body.automations_enabled,
        include_in_net=body.include_in_net,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account_json(db, account)


@router.patch("/accounts/{account_id}")
def patch_account(
    account_id: str,
    body: AccountPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    account = _owned_account(db, user, account_id)
    data = body.model_dump(exclude_unset=True)
    if "name" in data:
        account.name = data["name"].strip()
    if "type" in data:
        if data["type"] not in ACCOUNT_TYPES:
            raise HTTPException(400, "Unknown account type")
        account.type = data["type"]
    if "purpose" in data:
        if data["purpose"] not in PURPOSES:
            raise HTTPException(400, "Unknown account purpose")
        account.purpose = data["purpose"]
    if "bank_name" in data:
        account.bank_name = (data["bank_name"] or "").strip()
    if "last4" in data:
        digits = re.sub(r"\D", "", data["last4"] or "")
        account.last4 = digits[-4:] if digits else ""
    if "sms_sender" in data:
        account.sms_sender = (data["sms_sender"] or "").strip()
    if "opening_balance" in data:
        account.opening_balance = data["opening_balance"]
    if "automations_enabled" in data:
        account.automations_enabled = data["automations_enabled"]
    if "include_in_net" in data:
        account.include_in_net = bool(data["include_in_net"])
    if "preferred" in data:
        account.preferred = bool(data["preferred"])
        if account.preferred:
            siblings = db.query(Account).filter(Account.user_id == user.id, Account.id != account.id, Account.archived.is_(False)).all()
            key = re.sub(r"[^A-Z0-9]", "", (account.sms_sender or account.bank_name or "").upper())
            for sibling in siblings:
                other = re.sub(r"[^A-Z0-9]", "", (sibling.sms_sender or sibling.bank_name or "").upper())
                if key and other == key:
                    sibling.preferred = False
    if "archived" in data:
        account.archived = data["archived"]
    db.commit()
    db.refresh(account)
    return account_json(db, account)


class CardLinkIn(BaseModel):
    last4: str

    @field_validator("last4")
    @classmethod
    def clean_card(cls, value: str) -> str:
        digits = re.sub(r"\D", "", value or "")
        if len(digits) < 4:
            raise ValueError("Enter the last 4 digits")
        return digits[-4:]


@router.post("/accounts/{account_id}/cards")
def link_card(
    account_id: str,
    body: CardLinkIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    account = _owned_account(db, user, account_id)
    remember_card(account, body.last4)
    pending = (
        db.query(Transaction)
        .filter_by(user_id=user.id, status="needs_review", card_last4=body.last4)
        .all()
    )
    for txn in pending:
        txn.account_id = account.id
        txn.scope = account.purpose
        txn.status = "posted"
        apply_withdrawal_transfer(db, user, txn)
    db.commit()
    db.refresh(account)
    return account_json(db, account)


@router.delete("/accounts/{account_id}")
def delete_account(account_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    account = _owned_account(db, user, account_id)
    used = (
        db.query(Transaction)
        .filter(
            Transaction.user_id == user.id,
            (Transaction.account_id == account.id) | (Transaction.transfer_account_id == account.id),
        )
        .count()
    )
    if used:
        account.archived = True
        db.commit()
        return {"archived": True}
    db.delete(account)
    db.commit()
    return {"deleted": True}


@router.get("/categories")
def list_categories(user: User = Depends(current_user), db: Session = Depends(get_db)):
    counts: dict[str, int] = {}
    for txn in db.query(Transaction).filter_by(user_id=user.id, status="posted").all():
        if txn.category_id:
            counts[txn.category_id] = counts.get(txn.category_id, 0) + 1
    rows = (
        db.query(Category)
        .filter_by(user_id=user.id)
        .order_by(Category.kind, Category.sort_order, Category.name)
        .all()
    )
    return [
        {
            "id": row.id,
            "name": row.name,
            "kind": row.kind,
            "icon": row.icon,
            "color": row.color,
            "parent_id": row.parent_id,
            "transaction_count": counts.get(row.id, 0),
        }
        for row in rows
    ]


@router.post("/categories")
def create_category(body: CategoryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    exists = db.query(Category).filter_by(user_id=user.id, kind=body.kind, name=body.name).first()
    if exists:
        raise HTTPException(400, "That category already exists")
    parent_id = None
    if body.parent_id:
        parent = _owned_category(db, user, body.parent_id)
        if parent.kind != body.kind:
            raise HTTPException(400, "A subcategory has to match its category")
        if parent.parent_id:
            raise HTTPException(400, "Add this under the main category")
        parent_id = parent.id
    row = Category(
        user_id=user.id,
        name=body.name,
        kind=body.kind,
        icon=body.icon,
        color=body.color,
        parent_id=parent_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return {
        "id": row.id,
        "name": row.name,
        "kind": row.kind,
        "icon": row.icon,
        "color": row.color,
        "parent_id": row.parent_id,
        "transaction_count": 0,
    }


@router.delete("/categories/{category_id}")
def delete_category(category_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = _owned_category(db, user, category_id)
    used = db.query(Transaction).filter_by(user_id=user.id, category_id=row.id).count()
    if used:
        raise HTTPException(400, "This category still has transactions")
    children = db.query(Category).filter_by(user_id=user.id, parent_id=row.id).count()
    if children:
        raise HTTPException(400, "Remove its subcategories first")
    db.delete(row)
    db.commit()
    return {"deleted": True}


@router.get("/transactions")
def list_transactions(
    status: str = "posted",
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(Transaction)
        .filter_by(user_id=user.id, status=status)
        .order_by(Transaction.occurred_at.desc())
        .all()
    )
    accounts = account_map(db, user.id)
    categories = category_map(db, user.id)
    return [txn_json(row, accounts, categories) for row in rows]


@router.post("/transactions")
def create_transaction(body: TxnIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    account = _owned_account(db, user, body.account_id)
    category = _owned_category(db, user, body.category_id)
    other = None
    if body.direction == "transfer":
        if not body.transfer_account_id or body.transfer_account_id == account.id:
            raise HTTPException(400, "Pick a different account to transfer to")
        other = _owned_account(db, user, body.transfer_account_id)
    merchant = body.merchant.strip()
    if body.direction == "transfer":
        if not merchant:
            merchant = "Transfer"
    elif not merchant:
        raise HTTPException(400, "Add a name for this transaction")
    charge = body.bank_charge if body.direction == "transfer" else Decimal("0")
    scope = body.scope or account.purpose
    if scope not in PURPOSES:
        raise HTTPException(400, "Unknown scope")
    if category and category.kind == "income" and body.direction == "expense":
        raise HTTPException(400, "That category is for income")
    if category and category.kind == "expense" and body.direction == "income":
        raise HTTPException(400, "That category is for expenses")
    txn = Transaction(
        user_id=user.id,
        account_id=account.id,
        transfer_account_id=other.id if other else None,
        category_id=category.id if category else None,
        direction=body.direction,
        amount=body.amount,
        bank_charge=charge,
        merchant=merchant,
        note=body.note.strip(),
        tags=_clean_tags(body.tags),
        occurred_at=(body.occurred_at or datetime.utcnow()).replace(tzinfo=None),
        scope=scope,
        source="manual",
        status="posted",
        hidden=body.hidden,
    )
    db.add(txn)
    db.commit()
    db.refresh(txn)
    return txn_json(txn, account_map(db, user.id), category_map(db, user.id))


@router.patch("/transactions/{txn_id}")
def patch_transaction(
    txn_id: str,
    body: TxnPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.user_id != user.id:
        raise HTTPException(404, "Transaction not found")
    data = body.model_dump(exclude_unset=True)
    if txn.direction == "loan" and "direction" in data and data["direction"] != "loan":
        raise HTTPException(400, "This entry belongs to a loan")
    if "account_id" in data and data["account_id"]:
        txn.account_id = _owned_account(db, user, data["account_id"]).id
    if "direction" in data and data["direction"]:
        if data["direction"] not in {"expense", "income", "transfer"}:
            raise HTTPException(400, "Unknown direction")
        txn.direction = data["direction"]
    if txn.direction == "transfer":
        other_id = data.get("transfer_account_id") or txn.transfer_account_id
        if not other_id or other_id == txn.account_id:
            raise HTTPException(400, "Pick a different account to transfer to")
        txn.transfer_account_id = _owned_account(db, user, other_id).id
        txn.category_id = None
        if "bank_charge" in data and data["bank_charge"] is not None:
            txn.bank_charge = data["bank_charge"]
    else:
        if "direction" in data:
            txn.transfer_account_id = None
            txn.bank_charge = Decimal("0")
        if "category_id" in data:
            category = _owned_category(db, user, data["category_id"])
            txn.category_id = category.id if category else None
    if "merchant" in data and data["merchant"]:
        txn.merchant = data["merchant"].strip()
    elif txn.direction == "transfer" and not (txn.merchant or "").strip():
        txn.merchant = "Transfer"
    if "note" in data:
        txn.note = (data["note"] or "").strip()
    if "tags" in data:
        txn.tags = _clean_tags(data["tags"] or "")
    if "scope" in data and data["scope"] in PURPOSES:
        txn.scope = data["scope"]
    if "amount" in data and data["amount"] is not None:
        txn.amount = data["amount"]
    if "hidden" in data and data["hidden"] is not None:
        txn.hidden = bool(data["hidden"])
    if "occurred_at" in data and data["occurred_at"] is not None:
        txn.occurred_at = data["occurred_at"].replace(tzinfo=None)
    db.commit()
    db.refresh(txn)
    return txn_json(txn, account_map(db, user.id), category_map(db, user.id))


@router.post("/transactions/{txn_id}/assign")
def assign_transaction(
    txn_id: str,
    body: AssignIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.user_id != user.id:
        raise HTTPException(404, "Transaction not found")
    account = _owned_account(db, user, body.account_id)
    category = _owned_category(db, user, body.category_id)
    txn.account_id = account.id
    txn.scope = account.purpose
    txn.status = "posted"
    if category:
        txn.category_id = category.id
    if txn.card_last4:
        remember_card(account, txn.card_last4)
        siblings = (
            db.query(Transaction)
            .filter_by(user_id=user.id, status="needs_review", card_last4=txn.card_last4)
            .all()
        )
        for sibling in siblings:
            sibling.account_id = account.id
            sibling.scope = account.purpose
            sibling.status = "posted"
            if category and sibling.category_id is None:
                sibling.category_id = category.id
            apply_withdrawal_transfer(db, user, sibling)
    apply_withdrawal_transfer(db, user, txn)
    db.commit()
    db.refresh(txn)
    return txn_json(txn, account_map(db, user.id), category_map(db, user.id))


@router.delete("/transactions/{txn_id}")
def delete_transaction(txn_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.user_id != user.id:
        raise HTTPException(404, "Transaction not found")
    if txn.loan_id:
        raise HTTPException(400, "This entry belongs to a loan. Record a repayment, or delete the loan.")
    db.delete(txn)
    db.commit()
    return {"deleted": True}


@router.post("/sms/ingest")
def sms_ingest(body: SmsIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    received = body.received_at.replace(tzinfo=None) if body.received_at else None
    return ingest_sms(db, user, body.body, body.sender, received, manual=body.manual)


@router.post("/sms/preview")
def sms_preview(body: SmsIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    parsed = parse_sms(body.body, body.received_at)
    account = match_account(db, user.id, parsed.last4, body.sender, body.body) if parsed.recognized else None
    return {
        "status": "matched" if account else ("recognized" if parsed.recognized else "ignored"),
        "parsed": parsed.as_dict(),
        "account_id": account.id if account else None,
        "account_name": account.name if account else "",
    }


def _repaid(db: Session, loan_id: str) -> Decimal:
    total = db.query(func.sum(LoanPayment.amount)).filter(LoanPayment.loan_id == loan_id).scalar()
    return Decimal(str(total or 0))


def _loan_label(loan: Loan, repayment: bool) -> str:
    if repayment:
        if loan.kind == "lend":
            return f"Repayment from {loan.party_name}"
        return f"Repayment to {loan.party_name}"
    if loan.kind == "lend":
        return f"Lent to {loan.party_name}"
    return f"Borrowed from {loan.party_name}"


def _movement_accounts(loan: Loan, reverse: bool, account_override: str | None) -> tuple[str | None, str | None]:
    if loan.kind == "lend":
        out_id, in_id = loan.account_id, loan.counterparty_account_id
    else:
        out_id, in_id = loan.counterparty_account_id, loan.account_id
    if reverse:
        out_id, in_id = in_id, out_id
        if loan.party_kind != "account" and account_override:
            if loan.kind == "lend":
                in_id = account_override
            else:
                out_id = account_override
    return out_id, in_id


def _post_loan_movement(
    db: Session,
    user: User,
    loan: Loan,
    amount: Decimal,
    reverse: bool,
    account_override: str | None,
    occurred_at: datetime,
) -> None:
    out_id, in_id = _movement_accounts(loan, reverse, account_override)
    if out_id is None and in_id is None:
        return
    anchor = db.get(Account, in_id) if in_id else None
    if anchor is None and out_id:
        anchor = db.get(Account, out_id)
    txn = Transaction(
        user_id=user.id,
        account_id=out_id,
        transfer_account_id=in_id,
        direction="loan",
        amount=amount,
        merchant=_loan_label(loan, reverse),
        note=loan.note or "",
        occurred_at=occurred_at.replace(tzinfo=None),
        scope=anchor.purpose if anchor else "personal",
        source="loan",
        status="posted",
        loan_id=loan.id,
    )
    db.add(txn)


def _loan_or_404(db: Session, user: User, loan_id: str) -> Loan:
    loan = db.get(Loan, loan_id)
    if loan is None or loan.user_id != user.id:
        raise HTTPException(404, "Loan not found")
    return loan


@router.get("/loans")
def list_loans(user: User = Depends(current_user), db: Session = Depends(get_db)):
    accounts = account_map(db, user.id)
    rows = db.query(Loan).filter_by(user_id=user.id).all()
    payload = [loan_json(row, accounts, _repaid(db, row.id)) for row in rows]
    payload.sort(key=lambda row: (row["settled"], row["due_on"] or "9999-12-31"))
    return payload


@router.post("/loans")
def create_loan(body: LoanIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    account = _owned_account(db, user, body.account_id) if body.account_id else None
    other = None
    if body.party_kind == "account":
        if account is None or not body.counterparty_account_id:
            raise HTTPException(400, "Choose both accounts")
        if body.counterparty_account_id == account.id:
            raise HTTPException(400, "Pick two different accounts")
        other = _owned_account(db, user, body.counterparty_account_id)
        party_name = other.name
    else:
        party_name = body.party_name.strip()
        if not party_name:
            raise HTTPException(400, "Add the person or business name")
    loan = Loan(
        user_id=user.id,
        kind=body.kind,
        party_kind=body.party_kind,
        party_name=party_name,
        counterparty_account_id=other.id if other else None,
        account_id=account.id if account else None,
        amount=body.amount,
        due_on=body.due_on,
        note=body.note.strip(),
        opened_at=utcnow(),
    )
    db.add(loan)
    db.flush()
    if account is not None or other is not None:
        _post_loan_movement(db, user, loan, body.amount, False, None, loan.opened_at)
    db.commit()
    db.refresh(loan)
    return loan_json(loan, account_map(db, user.id), Decimal("0"))


@router.post("/loans/{loan_id}/payments")
def repay_loan(
    loan_id: str,
    body: LoanPaymentIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    loan = _loan_or_404(db, user, loan_id)
    remaining = Decimal(str(loan.amount)) - _repaid(db, loan.id)
    if remaining <= 0:
        raise HTTPException(400, "This loan is already settled")
    if body.amount > remaining:
        raise HTTPException(400, "That is more than the amount still owed")
    account_override = None
    if body.account_id:
        account_override = _owned_account(db, user, body.account_id).id
    when = body.occurred_at or utcnow()
    payment = LoanPayment(
        loan_id=loan.id,
        user_id=user.id,
        amount=body.amount,
        account_id=account_override or loan.account_id,
        occurred_at=when.replace(tzinfo=None),
    )
    db.add(payment)
    _post_loan_movement(db, user, loan, body.amount, True, account_override, payment.occurred_at)
    db.commit()
    return loan_json(loan, account_map(db, user.id), _repaid(db, loan.id))


@router.delete("/loans/{loan_id}")
def delete_loan(loan_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    loan = _loan_or_404(db, user, loan_id)
    db.query(Transaction).filter_by(user_id=user.id, loan_id=loan.id).delete()
    db.query(LoanPayment).filter_by(loan_id=loan.id).delete()
    db.delete(loan)
    db.commit()
    return {"deleted": True}


def _advance(day: date, interval: str) -> date:
    if interval == "weekly":
        return day + timedelta(days=7)
    if interval == "yearly":
        try:
            return day.replace(year=day.year + 1)
        except ValueError:
            return day.replace(year=day.year + 1, month=2, day=28)
    month = day.month + 1
    year = day.year + (1 if month == 13 else 0)
    month = 1 if month == 13 else month
    last = date(year + (1 if month == 12 else 0), 1 if month == 12 else month + 1, 1) - timedelta(days=1)
    return date(year, month, min(day.day, last.day))


def _recurring_json(row: Recurring, accounts: dict[str, Account]) -> dict:
    account = accounts.get(row.account_id or "")
    return {
        "id": row.id,
        "kind": row.kind,
        "name": row.name,
        "amount": float(row.amount),
        "account_id": row.account_id,
        "account_name": account.name if account else "",
        "interval": row.interval,
        "next_on": row.next_on.isoformat(),
        "installments_total": row.installments_total,
        "installments_done": row.installments_done or 0,
        "active": row.active,
        "note": row.note or "",
    }


class RecurringIn(BaseModel):
    kind: str
    name: str
    amount: Decimal = Field(gt=0)
    account_id: str
    interval: str = "monthly"
    next_on: date
    installments_total: int | None = Field(default=None, ge=1, le=360)
    note: str = ""

    @field_validator("kind")
    @classmethod
    def clean_kind(cls, value: str) -> str:
        if value not in {"repeat", "installment", "subscription"}:
            raise ValueError("Unknown recurring type")
        return value

    @field_validator("interval")
    @classmethod
    def clean_interval(cls, value: str) -> str:
        if value not in {"weekly", "monthly", "yearly"}:
            raise ValueError("Unknown interval")
        return value

    @field_validator("name")
    @classmethod
    def clean_recurring_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Add a name")
        return value


@router.get("/recurring")
def list_recurring(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.query(Recurring).filter_by(user_id=user.id).order_by(Recurring.next_on, Recurring.created_at).all()
    accounts = account_map(db, user.id)
    return [_recurring_json(row, accounts) for row in rows]


@router.post("/recurring")
def create_recurring(body: RecurringIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    account = _owned_account(db, user, body.account_id)
    if body.kind == "installment" and not body.installments_total:
        raise HTTPException(400, "Add how many payments")
    row = Recurring(
        user_id=user.id,
        kind=body.kind,
        name=body.name,
        amount=body.amount,
        account_id=account.id,
        interval=body.interval,
        next_on=body.next_on,
        installments_total=body.installments_total if body.kind == "installment" else None,
        note=body.note.strip(),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _recurring_json(row, account_map(db, user.id))


@router.post("/recurring/{recurring_id}/pay")
def pay_recurring(recurring_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(Recurring, recurring_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(404, "Recurring item not found")
    if not row.active:
        raise HTTPException(400, "This series is finished")
    if not row.account_id:
        raise HTTPException(400, "Choose an account")
    account = _owned_account(db, user, row.account_id)
    txn = Transaction(
        user_id=user.id,
        account_id=account.id,
        direction="expense",
        amount=row.amount,
        merchant=row.name,
        note=row.note or "",
        occurred_at=datetime.combine(row.next_on, datetime.min.time()),
        scope=account.purpose,
        source="recurring",
        status="posted",
    )
    db.add(txn)
    row.installments_done = (row.installments_done or 0) + 1
    if row.kind == "installment" and row.installments_total and row.installments_done >= row.installments_total:
        row.active = False
    else:
        row.next_on = _advance(row.next_on, row.interval)
    db.commit()
    db.refresh(row)
    return _recurring_json(row, account_map(db, user.id))


@router.delete("/recurring/{recurring_id}")
def delete_recurring(recurring_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(Recurring, recurring_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(404, "Recurring item not found")
    db.delete(row)
    db.commit()
    return {"deleted": True}


@router.get("/dashboard")
def get_dashboard(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return dashboard(db, user)


@router.get("/insights")
def get_insights(month: str | None = None, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return insights(db, user, month)


@router.get("/timeline")
def get_timeline(
    month: str | None = None,
    account_id: str | None = None,
    scope: str | None = None,
    q: str | None = None,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return timeline(db, user, month, account_id, scope, q)


@router.get("/budgets")
def list_budgets(month: str | None = None, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return budget_rows(db, user, month)


@router.post("/budgets")
def create_budget(body: BudgetIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if not body.category_id:
        raise HTTPException(400, "Pick a category for this budget")
    _owned_category(db, user, body.category_id)
    taken = db.query(Budget).filter_by(user_id=user.id, category_id=body.category_id).first()
    if taken:
        raise HTTPException(400, "That category already has a budget")
    if body.account_id:
        _owned_account(db, user, body.account_id)
    row = Budget(
        user_id=user.id,
        name=body.name,
        category_id=body.category_id,
        account_id=body.account_id,
        limit_amount=body.limit_amount,
    )
    db.add(row)
    db.commit()
    return {"id": row.id}


@router.delete("/budgets/{budget_id}")
def delete_budget(budget_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(Budget, budget_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(404, "Budget not found")
    db.delete(row)
    db.commit()
    return {"deleted": True}


@router.get("/export.csv")
def export_csv(user: User = Depends(current_user), db: Session = Depends(get_db)):
    accounts = account_map(db, user.id)
    categories = category_map(db, user.id)
    rows = (
        db.query(Transaction)
        .filter_by(user_id=user.id, status="posted")
        .order_by(Transaction.occurred_at)
        .all()
    )
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        ["date", "direction", "amount", "bank_charge", "currency", "merchant", "category", "account", "scope", "source", "hidden", "note"]
    )
    for txn in rows:
        account = accounts.get(txn.account_id or "")
        category = categories.get(txn.category_id or "")
        writer.writerow(
            [
                txn.occurred_at.date().isoformat(),
                txn.direction,
                f"{Decimal(str(txn.amount)):.2f}",
                f"{Decimal(str(txn.bank_charge or 0)):.2f}",
                user.currency,
                txn.merchant,
                category.name if category else "",
                account.name if account else "",
                txn.scope,
                txn.source,
                "yes" if txn.hidden else "",
                txn.note or "",
            ]
        )
    return Response(
        content=buffer.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=folio.csv"},
    )
