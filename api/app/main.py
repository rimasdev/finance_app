from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import SessionLocal, configure
from app.routes import router
from app.services import repair_foreign_sms


@asynccontextmanager
async def lifespan(_app: FastAPI):
    configure()
    if SessionLocal is not None:
        db = SessionLocal()
        try:
            repair_foreign_sms(db)
        finally:
            db.close()
    yield


app = FastAPI(title="Takings", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(router)


@app.get("/health")
def health():
    return {"ok": True}
