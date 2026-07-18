"""Versioned `/api/v1` route package.

Feature routers are mounted here from Phase 2 onward. Health probes remain at
the process root (`/health/*`) and are not versioned under this prefix.
"""

from fastapi import APIRouter

from app.api.v1.me import router as me_router

router = APIRouter(prefix="/api/v1")
router.include_router(me_router)
