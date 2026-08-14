from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    ENV: str = "dev"

    # This backend's own public URL — swap per environment (localhost in dev, the
    # real VM/domain in prod) instead of hardcoding a host anywhere that builds a link.
    APP_BASE_URL: str = "http://localhost:8000"

    DATABASE_URL: str

    JWT_SECRET: str
    JWT_REFRESH_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    OTP_DEV_MODE: bool = True
    OTP_LENGTH: int = 6
    OTP_TTL_MINUTES: int = 10
    OTP_RESEND_COOLDOWN_SECONDS: int = 60
    OTP_MAX_ATTEMPTS_PER_CODE: int = 5
    OTP_MAX_REQUESTS_PER_EMAIL_PER_HOUR: int = 5
    OTP_MAX_REQUESTS_PER_IP_PER_HOUR: int = 20

    # Brute-force protection: failed *password* attempts per email in the window below.
    LOGIN_MAX_FAILED_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_WINDOW_MINUTES: int = 15

    # PDF spec's "3-day trial" gating sign-in — tracking scaffolding only for now
    # (see OPEN_QUESTIONS.md). Trial starts at User.created_at, so no separate
    # column is needed. Not enforced as a hard paywall yet: pricing tiers and a
    # payment provider (Stripe/RevenueCat/store IAP) haven't been decided, and
    # locking users out with no upgrade path would be a dead end. Exposed via
    # UserOut.is_trial_active/trial_expires_at so the client can show status
    # (e.g. a "N days left" banner) without the backend blocking access.
    TRIAL_DURATION_DAYS: int = 3

    # This account is seeded as is_admin=True by migration 20260814_add_admin_and_usage_limits
    # (owner request, 2026-08-14) — gets /admin/* access and is exempt from AI usage limits.
    ADMIN_EMAIL: str = "talk2saadalam@gmail.com"

    # Default AI message quota per rolling 30-day window (see api.deps.enforce_ai_usage_limit).
    # A per-user override lives on User.ai_monthly_limit, settable by the admin dashboard.
    # Chosen as a generous trial/free-tier allowance; paid tiers should raise this via the
    # per-user override until real subscription-tier defaults are decided.
    AI_USAGE_LIMIT_DEFAULT: int = 50

    # Exposes GET /api/v1/auth/_test/last-otp so E2E automation (Patrol) can read a
    # real OTP without IMAP access to a real inbox. The route itself doesn't exist
    # unless this is true. MUST stay false everywhere real user data can reach —
    # never set this in a shared/staging/prod .env, only as a one-off env var for a
    # disposable local test backend instance.
    TEST_MODE_OTP_BACKDOOR: bool = False

    # Azure Communication Services Email — the OTP delivery provider (see services/email.py).
    AZURE_COMMUNICATION_CONNECTION_STRING: str = ""
    AZURE_COMMUNICATION_SENDER: str = ""

    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_ID_ANDROID: str = ""
    GOOGLE_CLIENT_ID_IOS: str = ""

    APPLE_CLIENT_ID: str = ""
    APPLE_TEAM_ID: str = ""
    APPLE_KEY_ID: str = ""
    APPLE_PRIVATE_KEY_PATH: str = ""

    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_MODEL_HAIKU: str = "claude-haiku-4-5"
    ANTHROPIC_MODEL_SONNET: str = "claude-sonnet-5"
    ANTHROPIC_MODEL_OPUS: str = "claude-opus-5"

    # Kept server-side only (never sent to any client) so the legacy app's key-leak bug
    # (see DISCOVERY_REPORT.md) can't recur. See OPEN_QUESTIONS.md re: Gemini vs Anthropic
    # as the primary LLM provider going forward.
    GEMINI_API_KEY: str = ""

    AZURE_SEARCH_ENDPOINT: str = ""
    AZURE_SEARCH_KEY: str = ""
    AZURE_SEARCH_INDEX: str = "medaculous-knowledge"

    # Local-disk PDF storage for Knowledge Hub (OPEN_QUESTIONS.md: full sync,
    # local disk for now — a swap-in-place migration to S3/Blob later if
    # scale requires it, since nothing else needs to know where bytes live).
    PDF_STORAGE_DIR: str = "data/pdfs"
    PDF_MAX_UPLOAD_MB: int = 100

    # Profile photo storage — same local-disk-for-now approach as PDFs.
    AVATAR_STORAGE_DIR: str = "data/avatars"
    AVATAR_MAX_UPLOAD_MB: int = 5

    # Payment processor — not wired up yet. CheckoutScreen's final "Pay" step
    # shows a "this is coming soon" message instead of charging anything until
    # real keys land here and a backend charge/webhook endpoint exists.
    STRIPE_SECRET_KEY: str = ""
    STRIPE_PUBLISHABLE_KEY: str = ""

    @property
    def payments_configured(self) -> bool:
        return bool(self.STRIPE_SECRET_KEY)

    CORS_ORIGINS: str = "http://localhost:3000"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @property
    def is_prod(self) -> bool:
        return self.ENV.lower() == "prod"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
