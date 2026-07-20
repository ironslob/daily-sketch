"""Versioned `/api/v1` route package.

Feature routers are mounted here from Phase 2 onward. Health probes remain at
the process root (`/health/*`) and are not versioned under this prefix.
"""

from fastapi import APIRouter

from app.api.v1.feed import router as feed_router
from app.api.v1.me import router as me_router
from app.api.v1.prompts import router as prompts_router
from app.api.v1.safety import router as safety_router
from app.api.v1.sketch_sessions import router as sketch_sessions_router
from app.api.v1.social import reflections_router, router as social_router
from app.api.v1.submissions import router as submissions_router
from app.api.v1.uploads import router as uploads_router
from app.api.v1.users import router as users_router

router = APIRouter(prefix="/api/v1")
router.include_router(me_router)
router.include_router(users_router)
router.include_router(safety_router)
router.include_router(prompts_router)
router.include_router(feed_router)
router.include_router(sketch_sessions_router)
router.include_router(uploads_router)
router.include_router(submissions_router)
router.include_router(social_router)
router.include_router(reflections_router)
