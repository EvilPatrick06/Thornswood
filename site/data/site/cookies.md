# Cookies

Last changed: 22 October 2026.

The site uses storage for sign-in security and for your age statement, and
Cloudflare, which carries every connection to it, sets two cookies of its own
to keep scripts off it. It has no advertising cookies, Google Analytics, or
third-party tracking embeds.

| Name | Purpose | Duration |
| --- | --- | --- |
| `twa` | Signed Discord identity. Access is checked against Discord roles; signing in alone does not grant staff access. | Up to 30 days; cleared on sign-out. |
| `twst_*` | One-use security state during Discord sign-in, scoped to `/auth/discord`. | Ten minutes; cleared when the sign-in returns. |
| `tw` | Fallback member-password sign-in when Discord sign-in is not configured. Ignored when Discord is configured. | Up to one year; cleared on sign-out. |
| `tw-age-18` | Remembers that this browser stated eighteen or older. It does not verify age. | One year. |
| `__cf_bm` | Set by Cloudflare's Bot Fight Mode, not by the site: tells a browser apart from a script hammering the site. | Ends after 30 minutes of nothing. |
| `cf_clearance` | Set by Cloudflare, not by the site: says this browser passed Cloudflare's check, so it is not asked again. | Set by Cloudflare. |

The sign-in cookies are HttpOnly and SameSite=Lax. HTTPS adds Secure. The age
statement is also kept as `tw-age-18` in localStorage, which has no automatic
expiry. Clear site storage in your browser to remove that statement and make
the gate ask again. Clearing sign-in cookies signs you out.

These purposes support the services you request. The site does not load
optional analytics or advertising storage, so it has no optional-cookie
consent banner. Cloudflare Web Analytics, which counts page visits and load
times, stores nothing in your browser: no cookie and no localStorage (see
[Privacy](/privacy)). If tracking or embeds are added, their consent
requirements must be reviewed before they load.

See [Privacy](/privacy) for data use and deletion, and [Terms](/terms) for the
adult-content notice. Cookie rules depend on jurisdiction; this page describes
the actual storage rather than claiming universal legal compliance.
