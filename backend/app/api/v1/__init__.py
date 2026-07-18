"""Versioned `/api/v1` route package.

Feature routers are mounted here from Phase 2 onward. Health probes remain at
the process root (`/health/*`) and are not versioned under this prefix.
"""

from fastapi import APIRouter

from app.api.v1.feed import router as feed_router
from app.api.v1.me import router as me_router
from app.api.v1.prompts import router as prompts_router
from app.api.v1.users import router as users_router

router = APIRouter(prefix="/api/v1")
router.include_router(me_router)
router.include_router(users_router)
router.include_router(prompts_router)
router.include_router(feed_router)
