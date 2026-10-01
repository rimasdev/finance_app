import hashlib
import re
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.models import Account, Budget, Category, Transaction, User, utcnow
from app.sms_parser import parse_sms

EXPENSE_CATEGORIES = [
    ("Transport", "transport", "#7EB6FF"),
    ("Utilities", "utilities", "#F5C542"),
    ("Health care", "health", "#FF6B6B"),
    ("Debt payments", "debt", "#C084FC"),
    ("Dining out", "dining", "#FB923C"),
    ("Entertainment", "entertainment", "#F472B6"),
    ("Personal care", "personal", "#A78BFA"),
    ("Shopping", "shopping", "#34D399"),
    ("Gifts/Donation", "gifts", "#F87171"),
    ("Education", "education", "#60A5FA"),
    ("Work", "work", "#E7B8A3"),
    ("Transfers", "transfer", "#94A3B8"),
    ("Other", "other", "#9CA3AF"),
]
INCOME_CATEGORIES = [
    ("Salary", "salary", "#3DDC84"),
    ("Business income", "business", "#2DD4BF"),
    ("Transfers", "transfer", "#94A3B8"),
    ("Other income", "other", "#9CA3AF"),
]


def money(value) -> float:
    return float(Decimal(str(value)).quantize(Decimal("0.01")))


def seed_categories(db: Session, user_id: str) -> None:
    order = 0
    for name, icon, color in EXPENSE_CATEGORIES:
        db.add(Category(user_id=user_id, name=name, kind="expense", icon=icon, color=color, sort_order=order))
        order += 1
    order = 0
    for name, icon, color in INCOME_CATEGORIES:
        db.add(Category(user_id=user_id, name=name, kind="income", icon=icon, color=color, sort_order=order))
        order += 1


def user_json(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "name": user.name,
        "currency": user.currency,
        "timezone": user.timezone,
        "month_start_day": user.month_start_day,
    }


def period_bounds(year: int, month: int, start_day: int) -> tuple[date, date]:
    start_day = max(1, min(start_day, 28))
    start = date(year, month, start_day)
    if month == 12:
        next_year, next_month = year + 1, 1
    else:
        next_year, next_month = year, month + 1
    end = date(next_year, next_month, start_day) - timedelta(days=1)
    return start, end


def current_period_month(user: User, today: date | None = None) -> tuple[int, int]:
    tz = ZoneInfo(user.timezone or "Asia/Colombo")
    today = today or datetime.now(tz).date()
    start_day = max(1, min(user.month_start_day or 1, 28))
    if today.day >= start_day:
        return today.year, today.month
    if today.month == 1:
        return today.year - 1, 12
    return today.year, today.month - 1


def parse_month(value: str | None, user: User) -> tuple[int, int]:
    if value:
        year, month = value.split("-")
        return int(year), int(month)
    return current_period_month(user)


def utc_window(start: date, end: date, tzname: str) -> tuple[datetime, datetime]:
    tz = ZoneInfo(tzname or "Asia/Colombo")
    start_dt = datetime.combine(start, time.min, tz).astimezone(timezone.utc).replace(tzinfo=None)
    end_dt = datetime.combine(end + timedelta(days=1), time.min, tz).astimezone(timezone.utc).replace(tzinfo=None)
    return start_dt, end_dt


def to_utc(local_dt: datetime, tzname: str) -> datetime:
    tz = ZoneInfo(tzname or "Asia/Colombo")
    if local_dt.tzinfo is None:
        local_dt = local_dt.replace(tzinfo=tz)
    return local_dt.astimezone(timezone.utc).replace(tzinfo=None)


def iso(dt: datetime) -> str:
    return dt.replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")


def effect(txn: Transaction, account_id: str) -> Decimal:
    amount = Decimal(str(txn.amount))
    if txn.direction == "expense" and txn.account_id == account_id:
        return -amount
    if txn.direction == "income" and txn.account_id == account_id:
        return amount
    if txn.direction == "transfer":
        if txn.account_id == account_id:
            return -amount
        if txn.transfer_account_id == account_id:
            return amount
    return Decimal("0")


def account_balance(db: Session, account: Account) -> Decimal:
    rows = (
        db.query(Transaction)
        .filter(
            Transaction.user_id == account.user_id,
            Transaction.status == "posted",
            or_(Transaction.account_id == account.id, Transaction.transfer_account_id == account.id),
        )
        .all()
    )
    total = Decimal(str(account.opening_balance or 0))
    for row in rows:
        total += effect(row, account.id)
    return total


def account_json(db: Session, account: Account) -> dict:
    return {
        "id": account.id,
        "name": account.name,
        "type": account.type,
        "purpose": account.purpose,
        "bank_name": account.bank_name or "",
        "last4": account.last4 or "",
        "sms_sender": account.sms_sender or "",
        "opening_balance": money(account.opening_balance or 0),
        "balance": money(account_balance(db, account)),
        "automations_enabled": account.automations_enabled,
        "archived": account.archived,
    }


def category_map(db: Session, user_id: str) -> dict[str, Category]:
    return {c.id: c for c in db.query(Category).filter_by(user_id=user_id).all()}


def account_map(db: Session, user_id: str) -> dict[str, Account]:
    return {a.id: a for a in db.query(Account).filter_by(user_id=user_id).all()}


def txn_json(txn: Transaction, accounts: dict[str, Account], categories: dict[str, Category]) -> dict:
    account = accounts.get(txn.account_id or "")
    other = accounts.get(txn.transfer_account_id or "")
    category = categories.get(txn.category_id or "")
    return {
        "id": txn.id,
        "account_id": txn.account_id,
        "account_name": account.name if account else "",
        "transfer_account_id": txn.transfer_account_id,
        "transfer_account_name": other.name if other else "",
        "category_id": txn.category_id,
        "category_name": category.name if category else "",
        "category_icon": category.icon if category else "other",
        "category_color": category.color if category else "#9CA3AF",
        "direction": txn.direction,
        "amount": money(txn.amount),
        "merchant": txn.merchant,
        "note": txn.note or "",
        "occurred_at": iso(txn.occurred_at),
        "scope": txn.scope,
        "source": txn.source,
        "status": txn.status,
    }


def posted_in_window(db: Session, user: User, start: datetime, end: datetime) -> list[Transaction]:
    return (
        db.query(Transaction)
        .filter(
            Transaction.user_id == user.id,
            Transaction.status == "posted",
            Transaction.occurred_at >= start,
            Transaction.occurred_at < end,
        )
        .order_by(Transaction.occurred_at.desc())
        .all()
    )


def dashboard(db: Session, user: User) -> dict:
    year, month = current_period_month(user)
    start_d, end_d = period_bounds(year, month, user.month_start_day)
    start, end = utc_window(start_d, end_d, user.timezone)
    tz = ZoneInfo(user.timezone or "Asia/Colombo")
    now = datetime.now(tz)
    today_start, today_end = utc_window(now.date(), now.date(), user.timezone)
    accounts = db.query(Account).filter_by(user_id=user.id, archived=False).order_by(Account.created_at).all()
    categories = category_map(db, user.id)
    rows = posted_in_window(db, user, start, end)
    spent_today = Decimal("0")
    by_category: dict[str, Decimal] = {}
    for txn in rows:
        if txn.direction != "expense":
            continue
        if today_start <= txn.occurred_at < today_end:
            spent_today += Decimal(str(txn.amount))
        key = txn.category_id or ""
        by_category[key] = by_category.get(key, Decimal("0")) + Decimal(str(txn.amount))
    top = sorted(by_category.items(), key=lambda item: item[1], reverse=True)[:4]
    spenders = []
    for category_id, amount in top:
        category = categories.get(category_id)
        spenders.append(
            {
                "category_id": category_id or None,
                "name": category.name if category else "Uncategorised",
                "icon": category.icon if category else "other",
                "color": category.color if category else "#9CA3AF",
                "amount": money(amount),
            }
        )
    review_count = (
        db.query(Transaction).filter_by(user_id=user.id, status="needs_review").count()
    )
    return {
        "name": user.name,
        "currency": user.currency,
        "spent_today": money(spent_today),
        "accounts": [account_json(db, account) for account in accounts],
        "top_spenders": spenders,
        "review_count": review_count,
        "period": {"from": start_d.isoformat(), "to": end_d.isoformat()},
    }


def insights(db: Session, user: User, month_value: str | None) -> dict:
    year, month = parse_month(month_value, user)
    start_d, end_d = period_bounds(year, month, user.month_start_day)
    start, end = utc_window(start_d, end_d, user.timezone)
    categories = category_map(db, user.id)
    totals: dict[str, Decimal] = {}
    grand = Decimal("0")
    for txn in posted_in_window(db, user, start, end):
        if txn.direction != "expense":
            continue
        grand += Decimal(str(txn.amount))
        key = txn.category_id or ""
        totals[key] = totals.get(key, Decimal("0")) + Decimal(str(txn.amount))
    slices = []
    for category_id, amount in sorted(totals.items(), key=lambda item: item[1], reverse=True):
        category = categories.get(category_id)
        percent = float((amount / grand) * 100) if grand else 0
        slices.append(
            {
                "category_id": category_id or None,
                "name": category.name if category else "Uncategorised",
                "icon": category.icon if category else "other",
                "color": category.color if category else "#9CA3AF",
                "amount": money(amount),
                "percent": round(percent, 1),
            }
        )
    label = start_d.strftime("%B %Y")
    return {
        "label": label,
        "from": start_d.isoformat(),
        "to": end_d.isoformat(),
        "total": money(grand),
        "slices": slices,
    }


def _counts_for_header(txn: Transaction, account_id: str | None) -> str | None:
    if txn.direction == "expense":
        if account_id and txn.account_id != account_id:
            return None
        return "expense"
    if txn.direction == "income":
        if account_id and txn.account_id != account_id:
            return None
        return "income"
    if account_id is None:
        return None
    if txn.account_id == account_id:
        return "expense"
    if txn.transfer_account_id == account_id:
        return "income"
    return None


def timeline(
    db: Session,
    user: User,
    month_value: str | None,
    account_id: str | None,
    scope: str | None,
    query: str | None,
) -> dict:
    year, month = parse_month(month_value, user)
    start_d, end_d = period_bounds(year, month, user.month_start_day)
    start, end = utc_window(start_d, end_d, user.timezone)
    accounts = account_map(db, user.id)
    categories = category_map(db, user.id)
    income = Decimal("0")
    expenses = Decimal("0")
    days: dict[str, dict] = {}
    needle = (query or "").strip().lower()
    tz = ZoneInfo(user.timezone or "Asia/Colombo")
    for txn in posted_in_window(db, user, start, end):
        if scope in {"personal", "business"} and txn.scope != scope:
            continue
        if account_id and txn.account_id != account_id and txn.transfer_account_id != account_id:
            continue
        bucket = _counts_for_header(txn, account_id)
        if needle and needle not in (txn.merchant or "").lower() and needle not in (txn.note or "").lower():
            continue
        if bucket == "income":
            income += Decimal(str(txn.amount))
        elif bucket == "expense":
            expenses += Decimal(str(txn.amount))
        local_day = txn.occurred_at.replace(tzinfo=timezone.utc).astimezone(tz).date().isoformat()
        group = days.setdefault(local_day, {"date": local_day, "items": [], "total": Decimal("0")})
        signed = Decimal("0")
        if bucket == "income":
            signed = Decimal(str(txn.amount))
        elif bucket == "expense":
            signed = -Decimal(str(txn.amount))
        group["total"] += signed
        group["items"].append(txn_json(txn, accounts, categories))
    day_rows = []
    for key in sorted(days.keys(), reverse=True):
        group = days[key]
        day_rows.append(
            {
                "date": group["date"],
                "total": money(group["total"]),
                "items": group["items"],
            }
        )
    return {
        "label": start_d.strftime("%B %Y"),
        "from": start_d.isoformat(),
        "to": end_d.isoformat(),
        "income": money(income),
        "expenses": money(expenses),
        "net": money(income - expenses),
        "days": day_rows,
    }


def budget_rows(db: Session, user: User, month_value: str | None) -> list[dict]:
    year, month = parse_month(month_value, user)
    start_d, end_d = period_bounds(year, month, user.month_start_day)
    start, end = utc_window(start_d, end_d, user.timezone)
    categories = category_map(db, user.id)
    accounts = account_map(db, user.id)
    spent: dict[tuple[str | None, str | None], Decimal] = {}
    for txn in posted_in_window(db, user, start, end):
        if txn.direction != "expense":
            continue
        key = (txn.category_id, txn.account_id)
        spent[key] = spent.get(key, Decimal("0")) + Decimal(str(txn.amount))
    rows = []
    for budget in db.query(Budget).filter_by(user_id=user.id).order_by(Budget.created_at).all():
        used = Decimal("0")
        for (category_id, account_id), amount in spent.items():
            if budget.category_id and category_id != budget.category_id:
                continue
            if budget.account_id and account_id != budget.account_id:
                continue
            used += amount
        category = categories.get(budget.category_id or "")
        account = accounts.get(budget.account_id or "")
        limit = Decimal(str(budget.limit_amount))
        rows.append(
            {
                "id": budget.id,
                "name": budget.name,
                "category_id": budget.category_id,
                "category_name": category.name if category else "All categories",
                "category_icon": category.icon if category else "other",
                "category_color": category.color if category else "#9CA3AF",
                "account_id": budget.account_id,
                "account_name": account.name if account else "All accounts",
                "limit_amount": money(limit),
                "spent": money(used),
                "remaining": money(limit - used),
            }
        )
    return rows


def _norm(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (value or "").upper())


def match_account(db: Session, user_id: str, last4: str | None, sender: str, body: str) -> Account | None:
    accounts = db.query(Account).filter_by(user_id=user_id, archived=False).all()

    def sender_match(account: Account) -> bool:
        key = _norm(account.sms_sender) or _norm(account.bank_name)
        if len(key) < 3:
            return False
        sender_n = _norm(sender)
        if sender_n and (key in sender_n or sender_n in key):
            return True
        return key in _norm(body[:160])

    by_last4 = [account for account in accounts if account.last4 and last4 and account.last4 == last4[-4:]]
    if last4:
        if len(by_last4) == 1:
            return by_last4[0]
        if len(by_last4) > 1:
            narrowed = [account for account in by_last4 if sender_match(account)]
            return narrowed[0] if len(narrowed) == 1 else None
        return None
    by_sender = [account for account in accounts if sender_match(account)]
    return by_sender[0] if len(by_sender) == 1 else None


def _category_for_hint(db: Session, user_id: str, hint: str | None, direction: str) -> Category | None:
    if not hint:
        return None
    kind = "income" if direction == "income" else "expense"
    return (
        db.query(Category)
        .filter(Category.user_id == user_id, Category.kind == kind, Category.name.ilike(hint))
        .first()
    )


def body_hash(body: str) -> str:
    normalized = re.sub(r"\s+", " ", body).strip().lower()
    return hashlib.sha256(normalized.encode()).hexdigest()


def find_duplicate(db: Session, user_id: str, digest: str, fingerprint: str | None) -> Transaction | None:
    existing = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id, Transaction.sms_hash == digest)
        .first()
    )
    if existing:
        return existing
    if not fingerprint:
        return None
    since = utcnow() - timedelta(hours=72)
    return (
        db.query(Transaction)
        .filter(
            Transaction.user_id == user_id,
            Transaction.fingerprint == fingerprint,
            Transaction.created_at >= since,
        )
        .first()
    )


def ingest_sms(
    db: Session,
    user: User,
    body: str,
    sender: str = "",
    received_at: datetime | None = None,
    manual: bool = False,
) -> dict:
    parsed = parse_sms(body, received_at)
    accounts = account_map(db, user.id)
    categories = category_map(db, user.id)
    if not parsed.recognized:
        return {"status": "ignored", "reason": parsed.reason, "parsed": parsed.as_dict(), "transaction": None}

    digest = body_hash(body)
    duplicate = find_duplicate(db, user.id, digest, parsed.fingerprint)
    if duplicate:
        return {
            "status": "duplicate",
            "parsed": parsed.as_dict(),
            "transaction": txn_json(duplicate, accounts, categories),
        }

    account = match_account(db, user.id, parsed.last4, sender, body)
    if account and not account.automations_enabled and not manual:
        return {"status": "ignored", "reason": "automations_off", "parsed": parsed.as_dict(), "transaction": None}

    local_when = parsed.occurred_at or received_at or datetime.now()
    category = _category_for_hint(db, user.id, parsed.category_hint, parsed.direction or "expense")
    status = "posted" if account else "needs_review"
    txn = Transaction(
        user_id=user.id,
        account_id=account.id if account else None,
        category_id=category.id if category else None,
        direction=parsed.direction or "expense",
        amount=parsed.amount,
        merchant=parsed.merchant or "",
        occurred_at=to_utc(local_when, user.timezone),
        scope=account.purpose if account else "personal",
        source="sms",
        status=status,
        sms_hash=digest,
        fingerprint=parsed.fingerprint,
        raw_sms=body.strip(),
    )
    db.add(txn)
    db.commit()
    db.refresh(txn)
    accounts = account_map(db, user.id)
    categories = category_map(db, user.id)
    return {
        "status": status,
        "parsed": parsed.as_dict(),
        "transaction": txn_json(txn, accounts, categories),
    }

