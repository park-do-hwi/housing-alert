import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DB_URL = os.environ.get("HOUSING_DB_URL", "sqlite:///housing.db")


class Base(DeclarativeBase):
    pass


def make_engine(url: str = DB_URL):
    kwargs = {"connect_args": {"check_same_thread": False}} if url.startswith("sqlite") else {}
    return create_engine(url, **kwargs)


engine = make_engine()
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def init_db(eng=engine):
    from . import models  # noqa: F401
    Base.metadata.create_all(eng)
