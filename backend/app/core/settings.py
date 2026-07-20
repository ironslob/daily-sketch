"""Application settings loaded from environment variables."""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed runtime configuration for the Daily Sketch backend."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = Field(default="local", alias="APP_ENV")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    api_public_url: str = Field(default="http://localhost:8000", alias="API_PUBLIC_URL")
    release_version: str = Field(default="0.1.0", alias="RELEASE_VERSION")
    commit_sha: str = Field(default="unknown", alias="COMMIT_SHA")
    request_timeout_seconds: int = Field(default=30, alias="REQUEST_TIMEOUT_SECONDS")
    prompt_date_timezone: str = Field(default="UTC", alias="PROMPT_DATE_TIMEZONE")
    sketch_session_expiry_seconds: int = Field(
        default=86400,
        alias="SKETCH_SESSION_EXPIRY_SECONDS",
    )

    database_url: str = Field(
        default="postgresql+asyncpg://dailysketch:dailysketch@localhost:5432/dailysketch",
        alias="DATABASE_URL",
    )

    storage_endpoint: str = Field(default="http://localhost:9000", alias="STORAGE_ENDPOINT")
    storage_public_endpoint: str | None = Field(default=None, alias="STORAGE_PUBLIC_ENDPOINT")
    storage_region: str = Field(default="us-east-1", alias="STORAGE_REGION")
    storage_bucket: str = Field(default="dailysketch-local-media", alias="STORAGE_BUCKET")
    storage_access_key: str = Field(default="minioadmin", alias="STORAGE_ACCESS_KEY")
    storage_secret_key: str = Field(default="minioadmin", alias="STORAGE_SECRET_KEY")
    storage_use_ssl: bool = Field(default=False, alias="STORAGE_USE_SSL")

    allowed_image_content_types: str = Field(
        default="image/jpeg,image/png,image/webp",
        alias="ALLOWED_IMAGE_CONTENT_TYPES",
    )
    max_upload_bytes: int = Field(default=10_485_760, alias="MAX_UPLOAD_BYTES")
    signed_upload_expiry_seconds: int = Field(
        default=900,
        alias="SIGNED_UPLOAD_EXPIRY_SECONDS",
    )
    signed_read_expiry_seconds: int = Field(
        default=3600,
        alias="SIGNED_READ_EXPIRY_SECONDS",
    )
    caption_max_length: int = Field(default=280, alias="CAPTION_MAX_LENGTH")
    reflection_max_length: int = Field(default=500, alias="REFLECTION_MAX_LENGTH")

    descope_project_id: str = Field(default="replace-me", alias="DESCOPE_PROJECT_ID")
    descope_issuer: str = Field(
        default="https://api.descope.com/v1/apps/replace-me",
        alias="DESCOPE_ISSUER",
    )
    descope_audience: str = Field(default="replace-me", alias="DESCOPE_AUDIENCE")
    descope_jwks_url: str | None = Field(default=None, alias="DESCOPE_JWKS_URL")
    moderation_operator_token: str | None = Field(
        default=None,
        alias="MODERATION_OPERATOR_TOKEN",
    )

    @field_validator("request_timeout_seconds")
    @classmethod
    def validate_request_timeout(cls, value: int) -> int:
        if value < 1:
            raise ValueError("REQUEST_TIMEOUT_SECONDS must be at least 1")
        return value

    @field_validator("sketch_session_expiry_seconds")
    @classmethod
    def validate_sketch_session_expiry(cls, value: int) -> int:
        if value < 60:
            raise ValueError("SKETCH_SESSION_EXPIRY_SECONDS must be at least 60")
        return value

    @field_validator("max_upload_bytes")
    @classmethod
    def validate_max_upload_bytes(cls, value: int) -> int:
        if value < 1024:
            raise ValueError("MAX_UPLOAD_BYTES must be at least 1024")
        return value

    @field_validator("signed_upload_expiry_seconds", "signed_read_expiry_seconds")
    @classmethod
    def validate_signed_url_expiry(cls, value: int) -> int:
        if value < 60:
            raise ValueError("Signed URL expiry must be at least 60 seconds")
        return value

    @field_validator("caption_max_length")
    @classmethod
    def validate_caption_max_length(cls, value: int) -> int:
        if value < 1:
            raise ValueError("CAPTION_MAX_LENGTH must be at least 1")
        return value

    @field_validator("reflection_max_length")
    @classmethod
    def validate_reflection_max_length(cls, value: int) -> int:
        if value < 1:
            raise ValueError("REFLECTION_MAX_LENGTH must be at least 1")
        return value

    @field_validator("prompt_date_timezone")
    @classmethod
    def validate_prompt_date_timezone(cls, value: str) -> str:
        if value != "UTC":
            raise ValueError("PROMPT_DATE_TIMEZONE must be UTC in version one")
        return value

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, value: str) -> str:
        allowed = {"CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"}
        upper = value.upper()
        if upper not in allowed:
            raise ValueError(f"LOG_LEVEL must be one of {sorted(allowed)}")
        return upper

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def resolved_descope_jwks_url(self) -> str:
        if self.descope_jwks_url:
            return self.descope_jwks_url
        return f"https://api.descope.com/{self.descope_project_id}/.well-known/jwks.json"

    @property
    def allowed_image_content_type_set(self) -> frozenset[str]:
        return frozenset(
            part.strip().lower()
            for part in self.allowed_image_content_types.split(",")
            if part.strip()
        )

    @property
    def resolved_storage_public_endpoint(self) -> str:
        if self.storage_public_endpoint:
            return self.storage_public_endpoint
        return self.storage_endpoint


@lru_cache
def get_settings() -> Settings:
    return Settings()
