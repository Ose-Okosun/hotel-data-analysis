# Hotel Data Analysis (MySQL)

A SQL project in two parts: cleaning a deliberately messy hotel database, then using it to answer business questions a hotel manager might ask.

**Tool:** MySQL (Workbench)
**Skills shown:** data cleaning, JOIN / LEFT JOIN, GROUP BY / HAVING, CASE, CTEs (WITH), window functions (RANK, LAG), NOT EXISTS, date functions, aggregate functions

## The data

Five tables for a hotel (`lawyers_hub` database), built with planted errors:

| Table | Raw rows | After cleaning |
|---|---|---|
| guests | 160 | 150 |
| rooms | 42 | 41 |
| staff | 42 | 40 |
| bookings | 460 | 450 |
| outlet_orders | 1,012 | 1,000 |

## Part 1: Cleaning

Rules I followed:

- Never edit the raw tables. Work on copies.
- Remove exact duplicates with `SELECT DISTINCT`.
- Standardise text (spelling, capitals, spaces) with `CASE` and `LOWER(TRIM())`.
- Standardise dates that came in four different formats.
- Impossible values (negative amounts, ratings of 11, future hire dates) are set to NULL, not 0, because the true value is unknown.
- Flag, don't guess. Orphan IDs (a booking pointing to a guest or room that doesn't exist) are flagged and left unchanged.
- Every change is recorded in a `data_issue` column, so each fix can be traced.
- Only correct a value when the evidence is strong, for example recalculating a total where quantity, price, tax and tip prove it is wrong.

## Part 2: Business questions and findings

| Question | Finding |
|---|---|
| Which booking channel earns the most? | Direct: about 62.8 million from 132 bookings, roughly double Booking site (about 34.6 million, 87 bookings). |
| Which room type earns the most? | Suite (about 48.1 million, 76 bookings), then Presidential (about 43.3 million from only 27 bookings). |
| Which guests have never booked? | 11 guests. |
| Do loyalty tiers predict spending? | Not clearly. The top Silver guest spent more than the top Gold and Platinum guests. |
| Do guests who book far ahead spend more? | Bookings made 31+ days ahead average about 13% more (about 464,000 against about 410,000), with the same average stay of about 4 nights. |
| Which channel loses the most bookings to cancellation? | Direct has the most (10), but Expedia (12.5%) and Agent (12%) have higher cancellation rates than Direct (7.6%). |
| Which outlet loses the most orders to cancellation? | The Lounge, at about 15%, against about 10% across the hotel. |
| Which staff member sold the most? | A Restaurant server leads on volume, but one Spa server nearly matches their sales from far fewer orders. |

## Limits of this analysis

- Several groups are small. Expedia's 12.5% is 8 cancellations out of 64 bookings, so treat it as a pattern to watch, not a proven difference.
- The Spa has only 38 served orders, over half from one staff member. Its orders are worth much more each (about 55,000 against 9,000 to 22,000 elsewhere), but this needs more data before it can guide a decision.
- Revenue is not profit. No cost data was available.

## Files

- `lawyers_hub.sql`: builds the raw database
- (add your cleaning queries and analysis queries here, for example `01_cleaning.sql` and `02_analysis.sql`)
