---
name: project-knowledge
description: Use when the user asks about Move2Play products, product catalog, factories, lead times, warehouse locations, Google Sheets keys, BigQuery table schemas, SQL queries, FBA fees, inventory aging, settlements, return rates, bid automation, Walmart data, currency conversion, or needs to write queries against Move2Play data.
---

# Move2Play — Project Knowledge Base

## Product Catalog
Active products with factories and approximate lead times:

| Product Family | Products | Factory | COO | Lead Time (US) |
|---|---|---|---|---|
| Crawl Ball | Original, Texture, Girl | Jolly Toy / Dongguwan JT | China | ~105 days |
| Feed The Fish | Normal, Girl, Jungle, Wood | Propelus | India | ~70 days |
| Karaoke Machine | Pink, Blue/Green, Pink/Blue, Purple, Unicorn, Kidz Bop, Halloween, USA, Xmas, Teal/White | Tongheng / Jierul | China | ~105 days |
| KSK | Pink, Blue, Blue/Green, All Pink, Pink/Purple, Purple, Lavender, Xmas | Tongheng | China | ~105 days |
| Activity Table | Sun, Rainbow | Tongheng / Huizhou | China | ~105 days |
| Ball | Soccer, Football, Basketball, Baseball, Zebra, Unicorn, Giraffe | Launch / Plush | China | ~60 days |
| Dino Blower | Green - New, Green - Old, Pink | Dongguwan GV | China | ~60 days |
| Walker | 4in1 Giraffe, 4in1 Unicorn, Wooden | Various | China | ~105 days |
| Pass the Potato | Brown, Purple | SunLord / Dongguwan JT | India/China | ~105 days |
| RLGL | RLGL | Satish | India | ~75 days |
| Stacker | Turtle, Unicorn, Giraffe | Satish | India | ~75 days |
| Gym | Delux, Cheapo | Dongguwan JT / Jolly Toy | China | ~105 days |
| Wood | Cars, Stools | Dongguwan GV | China | ~60 days |
| Giraffe | Yellow, Pink | Satish | India | ~75 days |
| Dinosaur | Dinosaur | Satish | India | ~75 days |
| Bubble | Bunny, Fireworks, Halloween, Unicorn | Various | China | ~60 days |

## Warehouse Network
### US Warehouses (serve Amazon US + Walmart)
- **LMS** — primary 3PL
- **WHB** — secondary 3PL
- **ZonPrep** — prep center
- **AWD** — Amazon Warehousing & Distribution
- **Kain Logistics** — 3PL
- **Charles Kendall** — UK-based freight forwarder (holds some US-bound stock)

### Key Rule
- Amazon FBA inventory CANNOT be sent to Walmart
- Walmart inventory CANNOT be sent to Amazon
- Warehouse inventory (LMS, WHB, etc.) CAN be shipped to either
- CA and UK are completely separate inventory pools

## Google Sheets Reference

### Main Inventory Tracker
- Sheet: "2026 - Inventory tracker"
- Key: `1gxJsBiTG90TLRfiX0kISKVipCETNxOuGu3Ou1kpUSy8`

### Projection Sheets
| Region | Sheet Key |
|--------|-----------|
| USA | `1aVG3MOaQTW5o9D48oE7F2vo-zlOZWiwS50DypLWPDbw` |
| UK | `1IyNjy8Yy0rxvd17jI73YdLPK-bYDbFYWoLxc3Gs2kL0` |
| CA | `1zR_N4uiGTpcn_9rkpyPFWX2d0e5mXtqUX4jmgFQ6uxw` |
| Walmart | `1NI7aPFw2VSSVN0xVPoDdompfh0TLT5vbVDLLvVom3RA` |

### Google Ads Weekly Report
- Sheet: `1gx9K-MN1Lk9VDMcNrFrX_LdNBWEUsz-gRqSl59bXuO8`

## BigQuery Tables

GCP Project: `move2play-cloud`. Three main datasets: `amazon_data`, `walmart_data`, `sponsored_brands_products_bids`.

---

### Dataset: `amazon_data`

#### Orders
| Table | Description | Key Columns |
|-------|-------------|-------------|
| `all_orders_plus` | Amazon US orders | `date`, `asin`, `item-price`, `quantity`, `sales-channel` |
| `all_orders_plus_CAD` | Amazon CA orders (prices in CAD) | same as above |
| `all_orders_plus_GBP` | Amazon UK orders (prices in GBP) | same as above |

```sql
-- US orders
SELECT date, asin, `item-price`, quantity, `sales-channel`
FROM `move2play-cloud.amazon_data.all_orders_plus`
WHERE `sales-channel` = 'Amazon.com'
```

#### Product & Cost Reference
| Table | Type | Description | Key Columns |
|-------|------|-------------|-------------|
| `cogs_2026` | EXTERNAL | **Source of truth for product names & costs** | `ASIN`, `Product`, `COGs_Total`, `Revenue`, `FBA_Fee`, `Commission`, `Tariff_Rate`, `Tariff`, `COGs`, `Ocean`, `Logistics`, `Royalty`, `Ad_Spend`, `Returns`, `Profit`, `ROI`, `Tacos`, `Margin`, `Dollar_Bank`, `Return_Rate` |
| `productdata_2026` | EXTERNAL | Product reference data | ASIN, SKU, product details |
| `listing_content` | TABLE | Listing titles, bullets, backend keywords | `asin`, content fields |

```sql
-- Get canonical product names (ALWAYS use these, not Amazon listing titles)
SELECT DISTINCT ASIN, Product FROM `move2play-cloud.amazon_data.cogs_2026`
```

#### Advertising (append-only, MUST dedup)
| Table | Description | Partitioned | Clustered |
|-------|-------------|-------------|-----------|
| `ads_campaign_performance` | SP/SB hourly performance (Marketing Stream) | `report_date` (DAY) | `campaign_type`, `campaign_id` |
| `ads_report` | Historical ads reporting | - | - |
| `ads_report_brand` / `v2` / `v3` | Brand advertising attribution/spend | - | - |
| `ads_report_brand_search_term` | Brand search term data | - | - |
| `ads_budget_usage` | Campaign budget usage % | - | - |
| `campaign_oob_daily` | Out-of-budget daily tracking | `oob_date` (DAY) | `campaign_id` |
| `ads_hourly_seed` | Hourly ads seeding table | - | - |

**Critical**: All queries on `ads_campaign_performance` MUST use the dedup pattern:
```sql
SELECT campaign_id, report_date, hour, clicks, spend, impressions
FROM `move2play-cloud.amazon_data.ads_campaign_performance`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY campaign_id, report_date, hour
  ORDER BY run_timestamp DESC NULLS LAST
) = 1
```

Key columns: `run_date`, `run_timestamp`, `report_date`, `hour`, `campaign_type`, `campaign_id`, `campaign_name`, `campaign_status`, `impressions`, `clicks`, `spend`, `cost_per_click`, `purchases_7d`, `sales_7d`

#### Advertising Views
| View | Description |
|------|-------------|
| `ads_day_parting` | Hourly performance aggregation (includes dedup) |
| `ads_day_of_week` | Day-of-week performance patterns |
| `ads_day_parting_cvr` | Day-parting conversion rates |

#### Settlements & Fees
| Table | Description | Key Columns |
|-------|-------------|-------------|
| `settlements` | Amazon settlement line items | `settlement-id`, `transaction-type`, `order-id`, `marketplace-name`, `amount-type`, `amount-description`, `amount`, `sku`, `quantity-purchased` |
| `fee_estimates` | Per-ASIN fee estimates (US) | `run_date`, `marketplace`, `asin`, `sku`, `price_used`, `fba_fee`, `referral_fee`, `referral_fee_rate`, `total_fee` |
| `estimated_fees_CAD` | Fee estimates (CA) | same as above |
| `estimated_fees_GBP` | Fee estimates (UK) | same as above |
| `fba_fees_by_asin` | Detailed FBA fees per ASIN | Partitioned: `run_date` (DAY), Clustered: `marketplace`, `asin` |
| `fba_fee_rate_card` | 2026 FBA fee rate card (all size tiers) | size tier, fee amounts |
| `fba_fee_deviation_snapshot` | Point-in-time fee deviation data | ASIN, expected vs actual fees |

#### FBA Monitoring Views
| View | Description |
|------|-------------|
| `fba_fee_deviation_monitor` | Flags ASINs where actual FBA fees deviate from expected (cogs_2026) |
| `fba_low_inventory_alert` | ASINs with low-inventory fees active or approaching |
| `fba_fee_change_detection` | Detects FBA fee changes over time |
| `fba_asin_analysis` | Comprehensive per-ASIN FBA analysis |
| `fba_settlement_fee_monitor` | Fee analysis from settlement data |
| `fba_quarterly_storage_cost` | Quarterly storage cost tracking |
| `fba_storage_cost_by_asin` | Per-ASIN storage costs |
| `fifo_storage_duration` | FIFO-based storage duration tracking |
| `fba_remeasurement_tracking` | Tracks FBA remeasurement requests (`asin`, `submitted_date`, `status`, `case_id`) |

Note: Amazon's low-inventory fee and SIPP surcharge are baked into `FBAPerUnitFulfillmentFee` in settlements.

#### Inventory
| Table | Description | Key Columns |
|-------|-------------|-------------|
| `usa_fba_inventory` | FBA inventory snapshots | `snapshot_date`, `asin`, `sku`, `available`, `days_of_supply`, `low_inventory_level_fee_applied_in_current_week`, `fba_inventory_level_health_status`, `recommended_ship_in_quantity`, `inbound_quantity` |
| `ca_fba_inventory` | CA FBA inventory | same structure |
| `inventory_age_by_asin` | Inventory aging analysis | `run_date`, `marketplace`, `asin`, `total_units`, `inv_age_0_to_90_days`, `inv_age_91_to_180_days`, `inv_age_181_to_270_days`, `inv_age_271_to_365_days`, `inv_age_365_plus_days`, `avg_days_in_storage`, `sell_through`, `days_of_supply` |
| `inventory_ledger` | Inventory movement events | `run_date`, `marketplace`, `event_date`, `asin`, `event_type`, `reference_id`, `quantity`, `fulfillment_center`, `disposition`, `reason` |

Partitioning: `inventory_age_by_asin` and `inventory_ledger` are partitioned by `run_date` (DAY), clustered by `marketplace`, `asin`.

#### Returns
| Table | Description | Key Columns |
|-------|-------------|-------------|
| `return_rate_by_asin_cohort` | Return rates by ASIN and monthly cohort | `run_date`, `cohort_month`, `marketplace`, `asin`, `product_name`, `units_ordered`, `units_returned`, `return_rate`, `sellable_rate` |
| `return_rate_summary` | Aggregated return rate summary | marketplace, ASIN, rates |

#### Google Ads
| Table | Description |
|-------|-------------|
| `google_ads_performance` | Google Ads campaign performance |
| `google_ads_halo_sales` | Google Ads halo effect on Amazon sales |

#### Other Views
| View | Description |
|------|-------------|
| `master_move2play_sales_report` | Combined sales report across marketplaces |
| `listing_keyword_gaps` | Keywords missing from listings |
| `cogs` | Cost of goods (calculated view) |

---

### Dataset: `walmart_data`

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `walmart_all_orders` | Walmart orders | `order_date`, `sku`, `charge_amount`, `quantity` |
| `walmart_inventory` | Current Walmart inventory | sku, quantities |
| `walmart_items` | Walmart item catalog | sku, item details |
| `walmart_inbound_shipments` | Inbound shipment tracking | shipment details |
| `walmart_inbound_orders` | Inbound order details | order details |
| `sku_cogs` | Walmart SKU-level COGS | sku, cost fields |
| `v_walmart_daily_profit_estimated` | Daily profit estimate (VIEW) | date, sku, profit |
| `v_walmart_profit_per_sku_per_day` | Per-SKU daily profit (VIEW) | date, sku, revenue, costs |
| `v_walmart_sheets_import` | Sheets import view (VIEW) | formatted for Google Sheets |

```sql
SELECT order_date, sku, charge_amount, quantity
FROM `move2play-cloud.walmart_data.walmart_all_orders`
```

---

### Dataset: `sponsored_brands_products_bids`

Bid automation system for SP and SB campaigns. Key tables:

#### Campaign & Keyword Structure
| Table | Description |
|-------|-------------|
| `SP_Dynamic_Data_1_Live` | **Main SP performance + bid data** (campaign names, ad groups, keywords, bids, placement factors, optimization scores) |
| `SB_Dynamic_Data_1_Live` | Same for Sponsored Brands |
| `sp_campaign_list` / `sb_campaign_list` | Campaign lists |
| `sp_adgroup_list` / `sb_adgroup_list` | Ad group lists |
| `sp_keyword_list` / `sb_keyword_list` | Keyword lists |
| `sp_adgroups_targets_list` / `sb_adgroups_targets_list` | Product targeting lists |
| `ads_portfolios` | Portfolio lookup (`portfolio_id`, `portfolio_name`, `state`) |

#### Bid Automation
| Table | Description |
|-------|-------------|
| `sp_kw_bid_automation` | SP keyword bid automation settings (EXTERNAL/Google Sheet) |
| `sb_kw_bid_automation` | SB keyword bid automation settings (EXTERNAL/Google Sheet) |
| `sp_kw_bid_day_parting` / `sb_kw_bid_day_parting` | Day-parting bid adjustments (EXTERNAL) |
| `sp_kw_bid_history` / `sb_kw_bid_history` | Historical bid changes |
| `sp_hourly_spend_percentage` | Static hourly spend distribution (used for placement factor weighting) |
| `sp_gaussian_weights_v2` / `sb_gaussian_weights` | Gaussian weighting for bid optimization |

#### Key Views
| View | Description |
|------|-------------|
| `sp_kw_bid_automation_view` / `sb_kw_bid_automation_view` | Bid automation with calculated fields |
| `sb_kw_bid_history_view` | SB bid history with context |
| `sb_kw_placement_factor` / `sb_kw_placement_factor_calculated` | Placement factor calculations |
| `cloud_scheduler_jobs_view` | Scheduled job status monitoring |

---

### Key Query Patterns

#### 1. Ads Dedup (REQUIRED for all ads_campaign_performance queries)
```sql
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY campaign_id, report_date, hour
  ORDER BY run_timestamp DESC NULLS LAST
) = 1
```

#### 2. Latest Snapshot (for daily-partitioned tables)
```sql
-- Latest fee estimates
SELECT * FROM `move2play-cloud.amazon_data.fee_estimates`
WHERE run_date = (SELECT MAX(run_date) FROM `move2play-cloud.amazon_data.fee_estimates`)

-- Latest inventory age
SELECT * FROM `move2play-cloud.amazon_data.inventory_age_by_asin`
WHERE run_date = (SELECT MAX(run_date) FROM `move2play-cloud.amazon_data.inventory_age_by_asin`)
```

#### 3. Revenue by Product (with canonical names)
```sql
SELECT c.Product, SUM(o.`item-price`) as revenue, SUM(o.quantity) as units
FROM `move2play-cloud.amazon_data.all_orders_plus` o
JOIN `move2play-cloud.amazon_data.cogs_2026` c ON o.asin = c.ASIN
WHERE o.date >= '2026-01-01'
GROUP BY c.Product
ORDER BY revenue DESC
```

## Currency Conversion
- CAD -> USD: multiply by 0.73
- GBP -> USD: multiply by 1.27
- Walmart and Amazon US are already in USD

## Known Issues & Notes
- Amazon's `sbPurchasedProduct` API has been returning 0 rows since March 17, 2026 — SB Video brand attribution data is incomplete. 97 SB Video campaigns disappeared on March 16 (186 -> 89 active). The `sb_brand_attribution_fallback` view provides workaround logic
- PO Tracker may have duplicate entries (e.g., same order under two different PO numbers) — verify quantities if something looks doubled. Don't skip POs that are already in Packing List
- "Extra to Order" in Forecasting Check tabs = Q4 uplift quantities beyond base projections
- Marketing Stream data started 2026-03-12; backfill loaded on 2026-03-19 covers full S3 history. `ads_campaign_performance` uses append-only ingestion with `hours_back=24`
- For pacing/deal analysis: use Seller Central Orders data (not BigQuery) and join `ads_campaign_performance` with `ads_report` for ASIN-level ad spend

## 2026 Performance Snapshot (as of March 21, 2026)
- YTD Revenue: ~$3.4M across all marketplaces (+79% Y/Y)
- Projected Full Year: ~$35M (+77% Y/Y)
- Amazon US: $2.99M YTD (+76%), projected $29.9M full year
- Amazon UK: $198K YTD (+134%)
- Amazon CA: $150K YTD (+34%)
- Walmart: $43K YTD (new in 2025)
