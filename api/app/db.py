import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from sqlalchemy.pool import StaticPool

engine = None
SessionLocal = None


class Base(DeclarativeBase):
    pass


def _load_env_file() -> None:
    path = os.environ.get("ENV_FILE", ".env")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def configure() -> None:
    global engine, SessionLocal
    _load_env_file()
    url = os.environ.get("DATABASE_URL", "sqlite:///./data/folio.db")
    if url.startswith("sqlite:///") and url not in {"sqlite://", "sqlite:///:memory:"}:
        path = url.removeprefix("sqlite:///")
        folder = os.path.dirname(path)
        if folder:
            os.makedirs(folder, exist_ok=True)
    kwargs = {}
    if url.startswith("sqlite"):
        kwargs = {
            "connect_args": {"check_same_thread": False},
            "poolclass": StaticPool,
        }
    else:
        kwargs = {"pool_pre_ping": True}
    engine = create_engine(url, **kwargs)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    from app import models  # noqa: F401

    Base.metadata.create_all(engine)
    _ensure_user_columns()


def _ensure_user_columns() -> None:
    """Add sign-in columns on databases created before Apple and Google login."""
    from sqlalchemy import inspect, text

    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    present = {column["name"] for column in inspector.get_columns("users")}
    statements = []
    if "password_hash" in present:
        pass
    if "google_id" not in present:
        statements.append("ALTER TABLE users ADD COLUMN google_id VARCHAR(64)")
    if "apple_id" not in present:
        statements.append("ALTER TABLE users ADD COLUMN apple_id VARCHAR(64)")
    if "provider" not in present:
        statements.append("ALTER TABLE users ADD COLUMN provider VARCHAR(16) DEFAULT 'email'")
    user_bool = "0" if engine.dialect.name == "sqlite" else "FALSE"
    if "withdrawal_to_cash" not in present:
        statements.append(f"ALTER TABLE users ADD COLUMN withdrawal_to_cash BOOLEAN DEFAULT {user_bool}")
    if "cash_account_id" not in present:
        statements.append("ALTER TABLE users ADD COLUMN cash_account_id VARCHAR(36)")
    if "transactions" in inspector.get_table_names():
        txn_columns = {column["name"] for column in inspector.get_columns("transactions")}
        if "loan_id" not in txn_columns:
            statements.append("ALTER TABLE transactions ADD COLUMN loan_id VARCHAR(36)")
        bool_default = "0" if engine.dialect.name == "sqlite" else "FALSE"
        if "bank_charge" not in txn_columns:
            statements.append("ALTER TABLE transactions ADD COLUMN bank_charge NUMERIC(14, 2) DEFAULT 0")
        if "hidden" not in txn_columns:
            statements.append(f"ALTER TABLE transactions ADD COLUMN hidden BOOLEAN DEFAULT {bool_default}")
        if "card_last4" not in txn_columns:
            statements.append("ALTER TABLE transactions ADD COLUMN card_last4 VARCHAR(4) DEFAULT ''")
        if "tags" not in txn_columns:
            statements.append("ALTER TABLE transactions ADD COLUMN tags VARCHAR(200) DEFAULT ''")
    if "categories" in inspector.get_table_names():
        category_columns = {column["name"] for column in inspector.get_columns("categories")}
        if "parent_id" not in category_columns:
            statements.append("ALTER TABLE categories ADD COLUMN parent_id VARCHAR(36)")
    if "accounts" in inspector.get_table_names():
        account_columns = {column["name"] for column in inspector.get_columns("accounts")}
        bool_default = "0" if engine.dialect.name == "sqlite" else "FALSE"
        if "sort_order" not in account_columns:
            statements.append("ALTER TABLE accounts ADD COLUMN sort_order INTEGER DEFAULT 0")
        if "preferred" not in account_columns:
            statements.append(f"ALTER TABLE accounts ADD COLUMN preferred BOOLEAN DEFAULT {bool_default}")
        if "card_last4s" not in account_columns:
            statements.append("ALTER TABLE accounts ADD COLUMN card_last4s VARCHAR(80) DEFAULT ''")
        true_default = "1" if engine.dialect.name == "sqlite" else "TRUE"
        if "include_in_net" not in account_columns:
            statements.append(f"ALTER TABLE accounts ADD COLUMN include_in_net BOOLEAN DEFAULT {true_default}")
    if "loans" in inspector.get_table_names() and engine.dialect.name != "sqlite":
        due = next(
            (column for column in inspector.get_columns("loans") if column["name"] == "due_on"),
            None,
        )
        if due is not None and due.get("nullable") is False:
            statements.append("ALTER TABLE loans ALTER COLUMN due_on DROP NOT NULL")
    if not statements:
        return
    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))


def get_db():
    if SessionLocal is None:
        configure()
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
