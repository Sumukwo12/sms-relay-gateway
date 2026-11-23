// Public facts about the site, for metadata, robots.txt, the sitemap and
// structured data. Set NEXT_PUBLIC_SITE_URL when deploying elsewhere.

export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://sms.strand.co.ke").replace(/\/$/, "");

export const SITE_NAME = "SMS Gateway";

export const SITE_TITLE = "SMS Gateway: Send OTP & SMS From Your Own Android Phone";

export const SITE_DESCRIPTION =
  "Turn an Android phone into your own SMS gateway. Send verification codes (OTP) and notifications from your website through your SIM, with no per-message fees.";
