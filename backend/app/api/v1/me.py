"""Current-user routes."""

from fastapi import APIRouter, Depends

from app.auth.deps import get_current_user
from app.models.user import User
from app.schemas.me import CurrentUserResponse

router = APIRouter(tags=["me"])


@router.get("/me", response_model=CurrentUserResponse)
async def get_me(user: User = Depends(get_current_user)) -> CurrentUserResponse:
    return CurrentUserResponse.from_user(user)
