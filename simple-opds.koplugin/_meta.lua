local _ = require("gettext")
-- The version string is rewritten by .github/workflows/release.yml on every
-- push to main. Local checkouts keep "dev"; the release zip ships a
-- date-based version like "2026.5.31" or "2026.5.31.1" for same-day rebuilds.
return {
    name = "simple_opds",
    fullname = _("Simple OPDS"),
    description = _([[Clean OPDS browser with a cover grid and persistent Home / Recent / Genre / Search nav.]]),
    version = "dev",
}
