from datetime import date, datetime, timezone
from uuid import uuid4

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def new_id() -> str:
    return str(uuid4())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    google_id: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    apple_id: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    provider: Mapped[str] = mapped_column(String(16), default="email")
    currency: Mapped[str] = mapped_column(String(8), default="LKR")
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Colombo")
    month_start_day: Mapped[int] = mapped_column(default=1)
    withdrawal_to_cash: Mapped[bool] = mapped_column(Boolean, default=False)
    cash_account_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    accounts: Mapped[list["Account"]] = relationship(back_populates="user")
    categories: Mapped[list["Category"]] = relationship(back_populates="user")


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    type: Mapped[str] = mapped_column(String(20))
    purpose: Mapped[str] = mapped_column(String(20), default="personal")
    bank_name: Mapped[str] = mapped_column(String(80), default="")
    last4: Mapped[str] = mapped_column(String(4), default="")
    card_last4s: Mapped[str] = mapped_column(String(80), default="")
    sms_sender: Mapped[str] = mapped_column(String(40), default="")
    opening_balance: Mapped[float] = mapped_column(Numeric(14, 2), default=0)
    automations_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    preferred: Mapped[bool] = mapped_column(Boolean, default=False)
    include_in_net: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(default=0)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    user: Mapped[User] = relationship(back_populates="accounts")


class Category(Base):
    __tablename__ = "categories"
    __table_args__ = (UniqueConstraint("user_id", "kind", "name", name="uq_category_name"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[str] = mapped_column(String(16))
    icon: Mapped[str] = mapped_column(String(32), default="other")
    color: Mapped[str] = mapped_column(String(16), default="#9CA3AF")
    sort_order: Mapped[int] = mapped_column(default=0)
    parent_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), nullable=True)

    user: Mapped[User] = relationship(back_populates="categories")


class Transaction(Base):
    __tablename__ = "transactions"
    __table_args__ = (UniqueConstraint("user_id", "sms_hash", name="uq_sms_hash"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    transfer_account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    direction: Mapped[str] = mapped_column(String(16))
    amount: Mapped[float] = mapped_column(Numeric(14, 2))
    bank_charge: Mapped[float] = mapped_column(Numeric(14, 2), default=0)
    merchant: Mapped[str] = mapped_column(String(160), default="")
    note: Mapped[str] = mapped_column(Text, default="")
    tags: Mapped[str] = mapped_column(String(200), default="")
    occurred_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    scope: Mapped[str] = mapped_column(String(16), default="personal")
    source: Mapped[str] = mapped_column(String(16), default="manual")
    status: Mapped[str] = mapped_column(String(20), default="posted")
    hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    loan_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    sms_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    fingerprint: Mapped[str | None] = mapped_column(String(200), nullable=True)
    raw_sms: Mapped[str | None] = mapped_column(Text, nullable=True)
    card_last4: Mapped[str] = mapped_column(String(4), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Loan(Base):
    __tablename__ = "loans"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(16))
    party_kind: Mapped[str] = mapped_column(String(16))
    party_name: Mapped[str] = mapped_column(String(160))
    counterparty_account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    amount: Mapped[float] = mapped_column(Numeric(14, 2))
    due_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    note: Mapped[str] = mapped_column(Text, default="")
    opened_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class LoanPayment(Base):
    __tablename__ = "loan_payments"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    loan_id: Mapped[str] = mapped_column(ForeignKey("loans.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    amount: Mapped[float] = mapped_column(Numeric(14, 2))
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Recurring(Base):
    __tablename__ = "recurring"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(20))
    name: Mapped[str] = mapped_column(String(120))
    amount: Mapped[float] = mapped_column(Numeric(14, 2))
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    interval: Mapped[str] = mapped_column(String(16), default="monthly")
    next_on: Mapped[date] = mapped_column(Date)
    installments_total: Mapped[int | None] = mapped_column(nullable=True)
    installments_done: Mapped[int] = mapped_column(default=0)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    note: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Budget(Base):
    __tablename__ = "budgets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    limit_amount: Mapped[float] = mapped_column(Numeric(14, 2))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
