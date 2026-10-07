"""Turn a bank SMS into a transaction draft.

The matcher is generic on purpose. It looks for an amount, a debit or credit
verb, and optional account digits. It does not call any bank.
"""

import re
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

AMOUNT_RE = re.compile(
    r"(?i)(?:rs\.?|lkr|usd|eur|gbp)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"
)
DEBIT_RE = re.compile(
    r"(?i)\b(debited|debit|withdrawn|withdrawal|purchased|purchase|spent|deducted|charged)\b"
)
CREDIT_RE = re.compile(r"(?i)\b(credited|credit|deposited|deposit|received|refund(?:ed)?)\b")
OTP_RE = re.compile(r"(?i)\b(otp|one[- ]time password|verification code)\b")
DECLINED_RE = re.compile(
    r"(?i)\b(declined|insufficient funds|attempted transaction|unsuccessful|transaction failed|was not authorised|was not authorized)\b"
)
BALANCE_RE = re.compile(r"(?i)\b(?:avl|available|avbl|cleared)?\s*\.?\s*bal(?:ance)?\b")
LAST4_RES = [
    re.compile(r"(?i)(?:a/?c(?:ct|count)?|card|acct)\b[^\d]{0,20}(\d{4})\b"),
    re.compile(r"(?:\*{2,}|x{2,})(\d{4})\b", re.I),
    re.compile(r"(?i)\b(?:ending|no\.?)\s*#?\s*(\d{4})\b"),
]
MERCHANT_RES = [
    re.compile(r"(?i)\b(?:purchase|withdrawal|withdrawn)\s+at\s+(.+?)\s+(?:LK\s+)?for\b"),
    re.compile(
        r"(?i)(?:info|desc|description|details|narration|remarks?|merchant|ref|reference)\s*[:\-]\s*([A-Za-z0-9][A-Za-z0-9 .&'*/_-]{1,80})"
    ),
    re.compile(r"(?i)\b(?:at|towards)\s+([A-Za-z][A-Za-z0-9 .&'*/_-]{1,60})"),
]
DMY_RE = re.compile(r"\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b")
NAMED_DATE_RE = re.compile(
    r"(?i)\b(\d{1,2})[-\s](jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*[-\s,](\d{2,4})\b"
)
TIME_RE = re.compile(r"\b(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?\b", re.I)

MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}

CATEGORY_RULES = [
    (re.compile(r"(?i)uber|pickme|kangaroo|petrol|diesel|ceypetco|\bioc\b|fuel|filling station"), "Transport"),
    (re.compile(r"(?i)\b(dialog|mobitel|hutch|airtel|slt|lanka bell|leco|ceb|peo\s*tv)\b"), "Utilities"),
    (
        re.compile(
            r"(?i)keells|cargills|arpico|glomark|\bspar\b|supermarket|food\s*city|laughfs|"
            r"softlogic|cool planet"
        ),
        "Groceries",
    ),
    (re.compile(r"(?i)\b(toy|toys|kids mania)\b"), "Kids"),
    (re.compile(r"(?i)nolimit|odel|cotton collection|fashion"), "Dress"),
    (
        re.compile(
            r"(?i)\b(kfc|mcdonald|pizza|dominos|burger|subway|restaurant|cafe|coffee|dining|"
            r"bakery|bakers|baker|bar|pub|juice|lovers point)\b"
        ),
        "Day out",
    ),
    (re.compile(r"(?i)hospital|pharmacy|osusala|healthguard|asiri|nawaloka|dental|clinic|spa ceylon|\bhealth\b"), "Health"),
    (re.compile(r"(?i)netflix|spotify|youtube|apple\.com|google play|steam"), "Subscriptions"),
    (re.compile(r"(?i)cinema|movie|scope cinema"), "Day out"),
    (re.compile(r"(?i)\b(salary|payroll)\b"), "Salary"),
    (re.compile(r"(?i)islamic|quran|qur'an|madrasa|madarasa|hifz"), "Islamic class"),
    (re.compile(r"(?i)school|university|tuition|college"), "Education"),
    (re.compile(r"(?i)\b(fund transfer|online transfer|ceft|slip transfer)\b"), "Transfers"),
]


@dataclass
class ParsedSms:
    recognized: bool
    direction: str | None = None
    amount: Decimal | None = None
    currency: str | None = None
    last4: str | None = None
    merchant: str | None = None
    occurred_at: datetime | None = None
    balance: Decimal | None = None
    category_hint: str | None = None
    fingerprint: str | None = None
    reason: str | None = None
    withdrawal: bool = False

    def as_dict(self) -> dict:
        return {
            "recognized": self.recognized,
            "direction": self.direction,
            "amount": float(self.amount) if self.amount is not None else None,
            "currency": self.currency,
            "last4": self.last4,
            "merchant": self.merchant,
            "occurred_at": self.occurred_at.isoformat() if self.occurred_at else None,
            "balance": float(self.balance) if self.balance is not None else None,
            "category_hint": self.category_hint,
            "reason": self.reason,
            "withdrawal": self.withdrawal,
        }


def parse_sms(text: str, received_at: datetime | None = None) -> ParsedSms:
    raw = (text or "").strip()
    if not raw:
        return ParsedSms(False, reason="empty")
    if OTP_RE.search(raw):
        return ParsedSms(False, reason="otp")
    if DECLINED_RE.search(raw):
        return ParsedSms(False, reason="declined")

    amounts = [(m.start(), _decimal(m.group(1)), m.group(0)) for m in AMOUNT_RE.finditer(raw)]
    balance_at = BALANCE_RE.search(raw)
    balance = None
    amount = None
    currency = None
    if balance_at:
        for start, value, token in amounts:
            if start >= balance_at.start():
                balance = value
                break
    for start, value, token in amounts:
        if balance_at and start >= balance_at.start():
            continue
        amount = value
        currency = "USD" if token.lower().startswith("usd") else "LKR"
        if token.lower().startswith("eur"):
            currency = "EUR"
        if token.lower().startswith("gbp"):
            currency = "GBP"
        break

    debit = DEBIT_RE.search(raw)
    credit = CREDIT_RE.search(raw)
    if debit and credit:
        direction = "expense" if debit.start() < credit.start() else "income"
    elif debit:
        direction = "expense"
    elif credit:
        direction = "income"
    else:
        direction = None

    if amount is None or direction is None:
        return ParsedSms(False, reason="not_a_transaction")

    last4 = _last4(raw)
    merchant = _merchant(raw, direction)
    occurred = _when(raw, received_at)
    hint = _category_hint(raw, merchant, direction)
    withdrawal = looks_like_withdrawal(raw, merchant or "", direction)
    day = occurred.date().isoformat() if occurred else ""
    fingerprint = "|".join(
        [
            direction,
            f"{amount:.2f}",
            last4 or "",
            day,
            (merchant or "").lower(),
        ]
    )
    return ParsedSms(
        True,
        direction=direction,
        amount=amount,
        currency=currency,
        last4=last4,
        merchant=merchant,
        occurred_at=occurred,
        balance=balance,
        category_hint=hint,
        fingerprint=fingerprint,
        withdrawal=withdrawal,
    )


def looks_like_withdrawal(text: str, merchant: str = "", direction: str = "expense") -> bool:
    if direction != "expense":
        return False
    return bool(re.search(r"(?i)\b(withdrawn|withdrawal|\batm\b)\b", f"{merchant} {text}"))


def _decimal(token: str) -> Decimal:
    return Decimal(token.replace(",", ""))


def _last4(text: str) -> str | None:
    for pattern in LAST4_RES:
        match = pattern.search(text)
        if match:
            return match.group(1)[-4:]
    return None


def _merchant(text: str, direction: str) -> str:
    if re.search(r"(?i)\batm\b", text):
        return "ATM withdrawal" if direction == "expense" else "ATM deposit"
    for pattern in MERCHANT_RES:
        match = pattern.search(text)
        if not match:
            continue
        name = _clean_merchant(match.group(1))
        if name:
            return name
    return "Bank debit" if direction == "expense" else "Bank credit"


def _clean_merchant(name: str) -> str | None:
    name = re.split(r"(?i)\b(avl|available|bal|balance)\b", name)[0]
    name = name.strip(" .,-*")
    if len(name) < 2:
        return None
    if name.lower() in {"your", "the", "a", "rs", "lkr"}:
        return None
    return name[:80]


def _when(text: str, received_at: datetime | None) -> datetime:
    found = None
    named = NAMED_DATE_RE.search(text)
    numeric = DMY_RE.search(text)
    try:
        if named:
            year = int(named.group(3))
            if year < 100:
                year += 2000
            month = MONTHS[named.group(2).lower()[:3]]
            found = datetime(year, month, int(named.group(1)))
        elif numeric:
            year = int(numeric.group(3))
            if year < 100:
                year += 2000
            found = datetime(year, int(numeric.group(2)), int(numeric.group(1)))
    except ValueError:
        found = None
    base = found or received_at or datetime.now()
    clock = TIME_RE.search(text)
    if clock and found is not None:
        hour = int(clock.group(1))
        minute = int(clock.group(2))
        second = int(clock.group(3) or 0)
        marker = (clock.group(4) or "").lower()
        if marker == "pm" and hour < 12:
            hour += 12
        if marker == "am" and hour == 12:
            hour = 0
        if hour <= 23 and minute <= 59:
            base = base.replace(hour=hour, minute=minute, second=second, microsecond=0)
    return base.replace(microsecond=0)


def _category_hint(text: str, merchant: str, direction: str) -> str | None:
    blob = f"{merchant} {text}"
    if direction == "income" and re.search(r"(?i)\b(salary|payroll)\b", blob):
        return "Salary"
    if direction == "income" and re.search(r"(?i)\btransfer\b", blob):
        return "Transfers"
    for pattern, name in CATEGORY_RULES:
        if name == "Salary":
            continue
        if pattern.search(blob):
            if name == "Transfers" and direction == "income":
                return "Transfers"
            if name == "Transfers" and direction == "expense":
                return "Transfers"
            if direction == "expense" and name not in {"Salary"}:
                return name
    return None
