# BigQuery Routines

Stored procedures in `move2play-cloud.sponsored_brands_products_bids` that back team-facing tables and dashboards. SQL here is the source of truth — deploy by running the file with `bq query --use_legacy_sql=false < <file>.sql`.

## sp_declining_spend_routine.sql

Rebuilds `sp_declining_spend` using the bid-cliff detector pattern (see [bid-cliffs skill](../skills/bid-cliffs/SKILL.md)).

**Triggered by:** scheduled query `sp_declining_spend` (every day 09:00 UTC = 1 AM PST).
**Read by:** Apps Script on the SP Dynamic Data sheet (`16o9JsAz-1GjgO2TPn_guEDVm8lumigRSdE2Saj8N8sg`) → tab "Declining" (daily 2 AM PST refresh).

**Filters applied:**
- Enabled campaigns/ad-groups/keywords only
- Pre-ACOS < 45%
- Pre spend ≥ $5/day
- Bid cut ≥ 5%
- Impressions dropped ≥ 50% per day post-change
- Impression drop > 2× the bid drop
- Bid change date in last 14 days, at least 3 days after change
- Post window excludes last 2 days (incomplete data)

Sorted by `lost_dollars_per_day DESC`.
