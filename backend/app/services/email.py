import logging
from functools import lru_cache

from azure.communication.email import EmailClient

from app.core.config import settings

logger = logging.getLogger("medaculous.email")

_PURPOSE_COPY = {
    "email_verification": "Verify your email",
    "password_reset": "Reset your password",
}


@lru_cache
def _get_client() -> EmailClient:
    return EmailClient.from_connection_string(settings.AZURE_COMMUNICATION_CONNECTION_STRING)


def _render_otp_email(code: str, purpose: str) -> tuple[str, str, str]:
    """Returns (subject, html, plain_text)."""
    heading = _PURPOSE_COPY.get(purpose, "Your verification code")
    subject = f"{heading} — Medaculous"

    html = f"""\
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{subject}</title>
  </head>
  <body style="margin:0; padding:0; background-color:#f1f5f9; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f1f5f9; padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px; width:100%; background-color:#ffffff; border-radius:20px; overflow:hidden; box-shadow:0 4px 24px rgba(15,23,42,0.08);">
            <tr>
              <td style="background:linear-gradient(135deg,#0d0e1a 0%,#3b0764 55%,#701a75 100%); padding:32px 32px 28px 32px; text-align:center;">
                <div style="font-family:Georgia,serif; font-size:22px; font-weight:700; color:#ffffff; letter-spacing:0.3px;">medaculous</div>
                <div style="font-size:11px; letter-spacing:1.5px; color:#c4b5fd; margin-top:4px; text-transform:uppercase;">AI Powered Medical Reference</div>
              </td>
            </tr>
            <tr>
              <td style="padding:36px 32px 8px 32px; text-align:center;">
                <h1 style="margin:0 0 8px 0; font-size:19px; color:#0f172a;">{heading}</h1>
                <p style="margin:0; font-size:14px; color:#64748b; line-height:1.5;">
                  Enter this code in the app to continue. It expires in {settings.OTP_TTL_MINUTES} minutes.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 32px;text-align:center;">
                <div style="display:inline-block; background-color:#f8fafc; border:1px solid #e2e8f0; border-radius:14px; padding:18px 28px;">
                  <span style="font-size:34px; font-weight:700; letter-spacing:10px; color:#3b0764; font-family:'Courier New',monospace;">{code}</span>
                </div>
              </td>
            </tr>
            <tr>
              <td style="padding:8px 32px 32px 32px; text-align:center;">
                <p style="margin:0; font-size:12.5px; color:#94a3b8; line-height:1.6;">
                  Didn't request this code? You can safely ignore this email — no changes will be made to your account.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 32px; text-align:center; background-color:#f8fafc; border-top:1px solid #f1f5f9;">
                <p style="margin:0; font-size:11px; color:#94a3b8;">Medaculous · Automated message, please do not reply.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>"""

    plain_text = (
        f"{heading}\n\nYour Medaculous verification code is: {code}\n\n"
        f"This code expires in {settings.OTP_TTL_MINUTES} minutes. "
        "If you didn't request this, you can safely ignore this email."
    )
    return subject, html, plain_text


def send_otp_email(to_email: str, code: str, purpose: str) -> None:
    if settings.OTP_DEV_MODE:
        # Dev/testing never depends on a live mail provider — the code just hits the logs.
        logger.info("[OTP_DEV_MODE] %s OTP for %s: %s", purpose, to_email, code)
        return

    subject, html, plain_text = _render_otp_email(code, purpose)
    client = _get_client()
    poller = client.begin_send(
        {
            "senderAddress": settings.AZURE_COMMUNICATION_SENDER,
            "recipients": {"to": [{"address": to_email}]},
            "content": {"subject": subject, "plainText": plain_text, "html": html},
        }
    )
    result = poller.result()
    logger.info("OTP email to %s: %s", to_email, result.get("status"))
