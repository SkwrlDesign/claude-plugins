---
name: listing-keyword-gap
description: Run a keyword gap analysis for an Amazon ASIN. Compares SP advertising search terms from the last 30 days against the listing content (title + bullets) to find important keywords that drive ad clicks but are missing from the listing. Output includes coverage summary, priority missing words, and full per-search-term gap detail.
---

# Listing Keyword Gap Report

Use this skill when the user asks for a keyword gap analysis, listing keyword gaps, or asks to find keywords missing from a listing for an ASIN.

## Inputs

- `asin` — required. Amazon ASIN (e.g. `B0D47JMDKM`).

## Step 1: Ensure listing content is loaded

Run the listing content loader to pull fresh listing data from the CatalogItems API into BQ:

```
python3 listing_content_loader.py <ASIN>
```

## Step 2: Get the product name

Query BQ for the product name from `cogs_2026`:

```sql
SELECT Product, ASIN FROM amazon_data.cogs_2026 WHERE ASIN = '<ASIN>'
```

If not found in `cogs_2026`, use the title from `listing_content` table.

## Step 3: Get listing content

Query BQ to retrieve the loaded listing data:

```sql
SELECT title, bullets, backend_keywords FROM amazon_data.listing_content WHERE asin = '<ASIN>'
```

## Step 4: Get coverage summary

Run this query to get total search terms vs gap terms:

```sql
WITH asin_campaigns AS (
  SELECT DISTINCT campaign_id FROM amazon_data.ads_report
  WHERE advertised_asin = '<ASIN>' AND marketplace = 'US'
    AND date >= FORMAT_DATE('%Y-%m-%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
),
all_terms AS (
  SELECT st.search_term, SUM(CAST(st.clicks AS INT64)) as clicks, SUM(st.purchases) as purchases, ROUND(SUM(st.sales),2) as sales
  FROM sponsored_brands_products_bids.search_terms_unified st
  INNER JOIN asin_campaigns ac ON st.campaign_id = ac.campaign_id
  WHERE st.ad_type = 'SP' AND st.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND st.marketplace = 'US'
    AND LOWER(st.search_term) NOT LIKE '%move2play%' AND LOWER(st.search_term) NOT LIKE '%b0%'
  GROUP BY st.search_term HAVING SUM(CAST(st.clicks AS INT64)) >= 10
),
gaps AS (
  SELECT * FROM amazon_data.listing_keyword_gaps WHERE asin = '<ASIN>' AND clicks >= 10
)
SELECT
  (SELECT COUNT(*) FROM all_terms) as total_terms,
  (SELECT SUM(clicks) FROM all_terms) as total_clicks,
  (SELECT SUM(purchases) FROM all_terms) as total_purchases,
  (SELECT ROUND(SUM(sales),2) FROM all_terms) as total_sales,
  (SELECT COUNT(*) FROM gaps) as gap_terms,
  (SELECT SUM(clicks) FROM gaps) as gap_clicks,
  (SELECT SUM(purchases) FROM gaps) as gap_purchases
```

## Step 5: Get keywords in bullets but not title

Parse the title and bullets from the `listing_content` table. Then run this query to find search terms where key words appear in bullets but not in the title:

```sql
CREATE TEMP FUNCTION stem(word STRING) AS (
  CASE
    WHEN LENGTH(word) > 4 AND ENDS_WITH(word, 'ing') THEN SUBSTR(word, 1, LENGTH(word) - 3)
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 'ies') THEN CONCAT(SUBSTR(word, 1, LENGTH(word) - 3), 'y')
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 'es') THEN SUBSTR(word, 1, LENGTH(word) - 2)
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 's') AND NOT ENDS_WITH(word, 'ss') THEN SUBSTR(word, 1, LENGTH(word) - 1)
    ELSE word
  END
);

WITH asin_campaigns AS (
  SELECT DISTINCT campaign_id FROM amazon_data.ads_report
  WHERE advertised_asin = '<ASIN>' AND marketplace = 'US'
    AND date >= FORMAT_DATE('%Y-%m-%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
),
search_terms AS (
  SELECT st.search_term, SUM(CAST(st.clicks AS INT64)) as clicks, SUM(st.purchases) as purchases, ROUND(SUM(st.sales),2) as sales
  FROM sponsored_brands_products_bids.search_terms_unified st
  INNER JOIN asin_campaigns ac ON st.campaign_id = ac.campaign_id
  WHERE st.ad_type = 'SP' AND st.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND st.marketplace = 'US'
    AND LOWER(st.search_term) NOT LIKE '%move2play%' AND LOWER(st.search_term) NOT LIKE '%b0%'
  GROUP BY st.search_term HAVING SUM(CAST(st.clicks AS INT64)) >= 10
),
title_text AS (
  SELECT LOWER(title) as title_lower FROM amazon_data.listing_content WHERE asin = '<ASIN>'
),
listing AS (
  SELECT all_content FROM amazon_data.listing_content WHERE asin = '<ASIN>'
),
bullet_only AS (
  SELECT st.search_term, st.clicks, st.purchases, st.sales,
    (SELECT STRING_AGG(word, ', ')
     FROM UNNEST(SPLIT(LOWER(st.search_term), ' ')) AS word
     WHERE word NOT IN ('for','the','a','to','and','of','with','in','on','is','it','my','+','|','&')
       AND LENGTH(word) > 1
       AND STRPOS(t.title_lower, word) = 0
       AND STRPOS(t.title_lower, stem(word)) = 0
       AND (STRPOS(l.all_content, word) > 0 OR STRPOS(l.all_content, stem(word)) > 0)
    ) as in_bullets_not_title
  FROM search_terms st CROSS JOIN title_text t CROSS JOIN listing l
)
SELECT search_term, clicks, purchases, sales, in_bullets_not_title
FROM bullet_only
WHERE in_bullets_not_title IS NOT NULL AND in_bullets_not_title != ''
ORDER BY clicks DESC
```

## Step 6: Get priority missing words (aggregated)

```sql
CREATE TEMP FUNCTION stem(word STRING) AS (
  CASE
    WHEN LENGTH(word) > 4 AND ENDS_WITH(word, 'ing') THEN SUBSTR(word, 1, LENGTH(word) - 3)
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 'ies') THEN CONCAT(SUBSTR(word, 1, LENGTH(word) - 3), 'y')
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 'es') THEN SUBSTR(word, 1, LENGTH(word) - 2)
    WHEN LENGTH(word) > 3 AND ENDS_WITH(word, 's') AND NOT ENDS_WITH(word, 'ss') THEN SUBSTR(word, 1, LENGTH(word) - 1)
    ELSE word
  END
);

WITH asin_campaigns AS (
  SELECT DISTINCT campaign_id FROM amazon_data.ads_report
  WHERE advertised_asin = '<ASIN>' AND marketplace = 'US'
    AND date >= FORMAT_DATE('%Y-%m-%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
),
search_terms AS (
  SELECT st.search_term, SUM(CAST(st.clicks AS INT64)) as clicks, SUM(st.purchases) as purchases, ROUND(SUM(st.sales),2) as sales
  FROM sponsored_brands_products_bids.search_terms_unified st
  INNER JOIN asin_campaigns ac ON st.campaign_id = ac.campaign_id
  WHERE st.ad_type = 'SP' AND st.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND st.marketplace = 'US'
    AND LOWER(st.search_term) NOT LIKE '%move2play%' AND LOWER(st.search_term) NOT LIKE '%b0%'
  GROUP BY st.search_term HAVING SUM(CAST(st.clicks AS INT64)) >= 10
),
listing AS (SELECT all_content FROM amazon_data.listing_content WHERE asin = '<ASIN>'),
missing AS (
  SELECT word, st.clicks, st.purchases, st.sales
  FROM search_terms st CROSS JOIN listing l
  CROSS JOIN UNNEST(SPLIT(LOWER(st.search_term), ' ')) AS word
  WHERE word NOT IN ('for','the','a','to','and','of','with','in','on','is','it','my','de','para','que','un','una','el','la','los','las','se','no','por','con','+','|','&','from')
    AND LENGTH(word) > 1
    AND STRPOS(l.all_content, word) = 0
    AND STRPOS(l.all_content, stem(word)) = 0
)
SELECT word, SUM(clicks) as total_clicks, SUM(purchases) as total_purchases, ROUND(SUM(sales),2) as total_sales,
       COUNT(*) as search_terms_count
FROM missing GROUP BY word ORDER BY total_clicks DESC LIMIT 20
```

## Step 7: Get full gap detail

```sql
SELECT search_term, clicks, impressions, spend, purchases, sales, missing_words, coverage
FROM amazon_data.listing_keyword_gaps
WHERE asin = '<ASIN>' AND clicks >= 10
ORDER BY clicks DESC
```

## Output Format

Output the report EXACTLY in this format (replace values with actual data). Use the product name from `cogs_2026`, NOT the Amazon listing title.

### Listing Keyword Gap Report

**ASIN:** <ASIN>
**Product:** <product name from cogs_2026>
**Period:** Last 30 days | **Marketplace:** US

**Listing Content:**
- Title: <full title>
- Bullets: <abbreviated to key phrases>
- Backend Search Terms: Not accessible via API. Check Seller Central > Edit Listing > Keywords tab.

**Coverage Summary:** <total terms> search terms with 10+ clicks, <gap terms> (<pct>%) have keyword gaps

**Keywords in Bullets but NOT in Title:** Table showing words that appear in bullet points and drive ad clicks, but are missing from the title

**Priority Missing Words:** Top 20 words not found anywhere in the listing (title, bullets, or stems), sorted by total clicks

**Full Gap Detail (10+ Clicks):** All search terms with gaps, showing clicks, impressions, spend, purchases, sales, missing words, and coverage %

## Formatting rules

- Use product name from BQ `amazon_data.cogs_2026`, NOT the Amazon listing title.
- Abbreviate bullets to key phrases (not full text).
- Combine related missing words on one line where it makes sense (e.g., "first / 1st").
- Include ALL search terms with 10+ clicks including Spanish terms.
- Format dollar amounts with `$` and commas for thousands.
- Sort full gap detail by clicks descending.
