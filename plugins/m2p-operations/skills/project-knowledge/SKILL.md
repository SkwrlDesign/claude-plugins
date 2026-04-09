---
name: project-knowledge
description: Use when the user asks about Move2Play products, product catalog, factories, lead times, warehouse locations, Google Sheets keys, BigQuery table schemas, currency conversion rates, or needs to write SQL queries against Move2Play data.
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

### Amazon Orders
```sql
-- US orders
SELECT date, asin, `item-price`, quantity, `sales-channel`
FROM `move2play-cloud.amazon_data.all_orders_plus`
WHERE `sales-channel` = 'Amazon.com'

-- CA orders (prices in CAD)
SELECT date, asin, `item-price`, quantity
FROM `move2play-cloud.amazon_data.all_orders_plus_CAD`

-- UK orders (prices in GBP)
SELECT date, asin, `item-price`, quantity
FROM `move2play-cloud.amazon_data.all_orders_plus_GBP`
```

### Walmart Orders
```sql
SELECT order_date, sku, charge_amount, quantity
FROM `move2play-cloud.walmart_data.walmart_all_orders`
```

### Advertising (MUST use dedup pattern)
```sql
SELECT campaign_id, report_date, hour, clicks, spend, impressions
FROM `move2play-cloud.amazon_data.ads_campaign_performance`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY campaign_id, report_date, hour
  ORDER BY run_timestamp DESC NULLS LAST
) = 1
```

## Currency Conversion
- CAD → USD: multiply by 0.73
- GBP → USD: multiply by 1.27
- Walmart and Amazon US are already in USD

## Known Issues & Notes
- Amazon's `sbPurchasedProduct` API has been returning 0 rows since March 17, 2026 — SB Video brand attribution data is incomplete
- PO Tracker may have duplicate entries (e.g., same order under two different PO numbers) — verify quantities if something looks doubled
- "Extra to Order" in Forecasting Check tabs = Q4 uplift quantities beyond base projections
