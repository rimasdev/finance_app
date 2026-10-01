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
