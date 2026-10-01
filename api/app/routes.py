import csv
import io
import re
from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.auth import decode_token, hash_password, make_token, verify_password
from app.db import get_db
from app.models import Account, Budget, Category, Transaction, User
from app.oauth import OAuthError, verify_apple_id_token, verify_google_id_token
from app.services import (
    account_json,
    account_map,
    budget_rows,
    category_map,
    dashboard,
    ingest_sms,
    insights,
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


class AccountIn(BaseModel):
    name: str
    type: str
    purpose: str = "personal"
    bank_name: str = ""
    last4: str = ""
    sms_sender: str = ""
    opening_balance: Decimal = Decimal("0")
    automations_enabled: bool = True

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
    archived: bool | None = None


class CategoryIn(BaseModel):
    name: str
    kind: str
    icon: str = "other"
    color: str = "#9CA3AF"

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


class TxnIn(BaseModel):
    account_id: str
    direction: str
    amount: Decimal = Field(gt=0)
    merchant: str
    category_id: str | None = None
    transfer_account_id: str | None = None
    occurred_at: datetime | None = None
    note: str = ""
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
        value = value.strip()
        if not value:
            raise ValueError("Add a name for this transaction")
        return value


class TxnPatch(BaseModel):
    account_id: str | None = None
    category_id: str | None = None
    merchant: str | None = None
    note: str | None = None
    scope: str | None = None
    amount: Decimal | None = Field(default=None, gt=0)
    occurred_at: datetime | None = None


class AssignIn(BaseModel):
    account_id: str
    category_id: str | None = None


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
    db.commit()
    db.refresh(user)
    return user_json(user)


@router.delete("/me")
def delete_me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.query(Budget).filter_by(user_id=user.id).delete()
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
        .order_by(Account.created_at)
        .all()
    )
    return [account_json(db, row) for row in rows]


@router.post("/accounts")
def create_account(body: AccountIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    opening = body.opening_balance
    if body.type == "credit_card" and opening > 0:
        opening = -opening
    account = Account(
        user_id=user.id,
        name=body.name,
        type=body.type,
        purpose=body.purpose,
        bank_name=body.bank_name.strip(),
        last4=body.last4,
        sms_sender=body.sms_sender.strip(),
        opening_balance=opening,
        automations_enabled=body.automations_enabled,
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
    if "archived" in data:
        account.archived = data["archived"]
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
            "transaction_count": counts.get(row.id, 0),
        }
        for row in rows
    ]


@router.post("/categories")
def create_category(body: CategoryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    exists = db.query(Category).filter_by(user_id=user.id, kind=body.kind, name=body.name).first()
    if exists:
        raise HTTPException(400, "That category already exists")
    row = Category(user_id=user.id, name=body.name, kind=body.kind, icon=body.icon, color=body.color)
    db.add(row)
    db.commit()
    db.refresh(row)
    return {
        "id": row.id,
        "name": row.name,
        "kind": row.kind,
        "icon": row.icon,
        "color": row.color,
        "transaction_count": 0,
    }


@router.delete("/categories/{category_id}")
def delete_category(category_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = _owned_category(db, user, category_id)
    used = db.query(Transaction).filter_by(user_id=user.id, category_id=row.id).count()
    if used:
        raise HTTPException(400, "This category still has transactions")
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
        merchant=body.merchant,
        note=body.note.strip(),
        occurred_at=(body.occurred_at or datetime.utcnow()).replace(tzinfo=None),
        scope=scope,
        source="manual",
        status="posted",
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
    if "account_id" in data and data["account_id"]:
        txn.account_id = _owned_account(db, user, data["account_id"]).id
    if "category_id" in data:
        category = _owned_category(db, user, data["category_id"])
        txn.category_id = category.id if category else None
    if "merchant" in data and data["merchant"]:
        txn.merchant = data["merchant"].strip()
    if "note" in data:
        txn.note = (data["note"] or "").strip()
    if "scope" in data and data["scope"] in PURPOSES:
        txn.scope = data["scope"]
    if "amount" in data and data["amount"] is not None:
        txn.amount = data["amount"]
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
    db.commit()
    db.refresh(txn)
    return txn_json(txn, account_map(db, user.id), category_map(db, user.id))


@router.delete("/transactions/{txn_id}")
def delete_transaction(txn_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.user_id != user.id:
        raise HTTPException(404, "Transaction not found")
    db.delete(txn)
    db.commit()
    return {"deleted": True}


@router.post("/sms/ingest")
def sms_ingest(body: SmsIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    received = body.received_at.replace(tzinfo=None) if body.received_at else None
    return ingest_sms(db, user, body.body, body.sender, received, manual=body.manual)


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
    _owned_category(db, user, body.category_id)
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
        ["date", "direction", "amount", "currency", "merchant", "category", "account", "scope", "source", "note"]
    )
    for txn in rows:
        account = accounts.get(txn.account_id or "")
        category = categories.get(txn.category_id or "")
        writer.writerow(
            [
                txn.occurred_at.date().isoformat(),
                txn.direction,
                f"{Decimal(str(txn.amount)):.2f}",
                user.currency,
                txn.merchant,
                category.name if category else "",
                account.name if account else "",
                txn.scope,
                txn.source,
                txn.note or "",
            ]
        )
    return Response(
        content=buffer.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=folio.csv"},
    )
