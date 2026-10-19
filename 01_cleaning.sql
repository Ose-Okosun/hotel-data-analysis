-- =====================================================================
-- 01_cleaning.sql
-- Database: lawyers_hub (MySQL)
-- Raw tables (never edited): guests, rooms, staff, bookings, outlet_orders
-- Working copies: bookings_clean, guests_clean, rooms_clean, staff_clean,
--                 outlet_orders2
--
-- Cleaning rules:
--   * never edit the raw tables, work on copies
--   * remove exact duplicates with SELECT DISTINCT
--   * impossible values are set to NULL (unknown) and a note is written
--     in the data_issue column
--   * flag, don't guess, unless the evidence is strong
--   * orphan IDs are flagged, not changed
--
-- Note: routine text and date fixes (spelling variants, capital letters,
-- date formats) are not included in this file. Where they belong, a line
-- says so. The flag queries below assume dates are already real dates.
-- =====================================================================

USE lawyers_hub;
SET SQL_SAFE_UPDATES = 0;


-- =====================================================================
-- 1. BOOKINGS  (bookings -> bookings_clean, 450 rows)
-- =====================================================================

-- bookings: remove exact duplicates (copy with SELECT DISTINCT)
DROP TABLE IF EXISTS bookings_clean;

CREATE TABLE bookings_clean AS
SELECT DISTINCT * FROM bookings;

-- bookings: standardise booking_status
UPDATE bookings_clean
SET booking_status = CASE
    WHEN LOWER(TRIM(booking_status)) IN ('completed', 'complete', 'checked out') THEN 'Completed'
    WHEN LOWER(TRIM(booking_status)) IN ('cancelled', 'canceled') THEN 'Cancelled'
    WHEN LOWER(TRIM(booking_status)) IN ('no-show', 'no show', 'noshow') THEN 'No-show'
    WHEN LOWER(TRIM(booking_status)) = 'confirmed' THEN 'Confirmed'
    ELSE booking_status
END;

-- Not included: routine text and date fixes for booking_channel, payment_method,
-- booking_date, check_in, check_out and cancellation_date.

-- bookings: add the notes column
ALTER TABLE bookings_clean ADD COLUMN data_issue VARCHAR(100);

-- bookings: check_out before check_in: flag only
UPDATE bookings_clean
SET data_issue = 'check_out before check_in'
WHERE check_out < check_in;

-- bookings: nights that don't match the dates (only where the dates are valid)
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'nights recalculated from dates'
        ELSE CONCAT(data_issue, '; nights recalculated from dates')
    END,
    nights = DATEDIFF(check_out, check_in)
WHERE check_out >= check_in
  AND nights <> DATEDIFF(check_out, check_in);

-- bookings: discount below 0 or above 100: set to NULL (unknown) and flag
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'discount out of range'
        ELSE CONCAT(data_issue, '; discount out of range')
    END,
    discount_pct = NULL
WHERE discount_pct < 0 OR discount_pct > 100;

-- bookings: adults below 1
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'adults below 1'
        ELSE CONCAT(data_issue, '; adults below 1')
    END,
    adults = NULL
WHERE adults < 1;

-- bookings: children below 0
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'children below 0'
        ELSE CONCAT(data_issue, '; children below 0')
    END,
    children = NULL
WHERE children < 0;

-- bookings: review_score outside 1 to 10
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'review_score out of range'
        ELSE CONCAT(data_issue, '; review_score out of range')
    END,
    review_score = NULL
WHERE review_score < 1 OR review_score > 10;

-- bookings: negative total_amount (sign typo): flip the sign
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'total_amount sign corrected'
        ELSE CONCAT(data_issue, '; total_amount sign corrected')
    END,
    total_amount = total_amount * -1
WHERE total_amount < 0;

-- bookings: cancellation_date on a booking that is not cancelled: flag only
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'cancellation_date on non-cancelled booking'
        ELSE CONCAT(data_issue, '; cancellation_date on non-cancelled booking')
    END
WHERE cancellation_date IS NOT NULL
  AND booking_status <> 'Cancelled';

-- bookings: recalculate blank totals and totals that break the rule
-- rule: nights * rate_applied * (1 - discount_pct / 100) + extras_amount + tax_amount
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'total_amount recalculated'
        ELSE CONCAT(data_issue, '; total_amount recalculated')
    END,
    total_amount = ROUND(nights * rate_applied * (1 - discount_pct / 100) + extras_amount + tax_amount, 2)
WHERE discount_pct IS NOT NULL
  AND (total_amount IS NULL
       OR total_amount NOT BETWEEN
          nights * rate_applied * (1 - discount_pct / 100) + extras_amount + tax_amount - 1
          AND nights * rate_applied * (1 - discount_pct / 100) + extras_amount + tax_amount + 1);

-- bookings: orphan guest_id (guest not in guests): flag only
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'guest_id not in guests'
        ELSE CONCAT(data_issue, '; guest_id not in guests')
    END
WHERE NOT EXISTS (
    SELECT 1
    FROM guests
    WHERE guests.guest_id = bookings_clean.guest_id
);

-- bookings: orphan room_id (room not in rooms): flag only
UPDATE bookings_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'room_id not in rooms'
        ELSE CONCAT(data_issue, '; room_id not in rooms')
    END
WHERE NOT EXISTS (
    SELECT 1
    FROM rooms
    WHERE rooms.room_id = bookings_clean.room_id
);


-- =====================================================================
-- 2. GUESTS  (guests -> guests_clean, 150 rows)
-- =====================================================================

-- guests: remove exact duplicates (copy with SELECT DISTINCT) -> 154 rows
DROP TABLE IF EXISTS guests_clean;

CREATE TABLE guests_clean AS
SELECT DISTINCT * FROM guests;

-- guests: names, stray spaces and capital letters
UPDATE guests_clean
SET first_name = CONCAT(UPPER(LEFT(TRIM(first_name), 1)), LOWER(SUBSTRING(TRIM(first_name), 2))),
    last_name  = CONCAT(UPPER(LEFT(TRIM(last_name), 1)),  LOWER(SUBSTRING(TRIM(last_name), 2)));

-- Not included: routine text and date fixes for country, gender, loyalty_tier
-- spelling, vip_flag, newsletter_opt_in, preferred_language, referral_source,
-- email, phone (+234 format), date_of_birth and registered_on.

-- guests: find the near-duplicate people (same name and birthday, different guest_id)
SELECT first_name, last_name, date_of_birth,
       COUNT(*) AS rows_found,
       MIN(guest_id) AS keep_id,
       MAX(guest_id) AS duplicate_id
FROM guests_clean
WHERE date_of_birth IS NOT NULL
GROUP BY first_name, last_name, date_of_birth
HAVING COUNT(*) > 1;

-- guests: check that no booking points at the duplicates (should return 0)
SELECT COUNT(*)
FROM bookings_clean
WHERE guest_id IN (151, 152, 153, 154);

-- guests: remove the 4 near-duplicate people (keep the lower guest_id)
DELETE FROM guests_clean
WHERE guest_id IN (151, 152, 153, 154);

-- guests: add the notes column
ALTER TABLE guests_clean ADD COLUMN data_issue VARCHAR(100);

-- guests: negative loyalty_points set to NULL and flagged
UPDATE guests_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'loyalty_points negative'
        ELSE CONCAT(data_issue, '; loyalty_points negative')
    END,
    loyalty_points = NULL
WHERE loyalty_points < 0;

-- guests: loyalty_tier blank or 'N/a' both mean unknown (11 rows)
-- label first (the next query finds its rows through this note)
UPDATE guests_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'no tier represented'
        ELSE CONCAT(data_issue, '; no tier represented')
    END
WHERE loyalty_tier IS NULL
   OR TRIM(loyalty_tier) = ''
   OR LOWER(TRIM(loyalty_tier)) = 'n/a';

UPDATE guests_clean
SET loyalty_tier = 'Unknown'
WHERE data_issue LIKE '%no tier represented%';


-- =====================================================================
-- 3. OUTLET ORDERS  (outlet_orders -> outlet_orders2, 1,000 rows)
-- =====================================================================

-- Not included: routine text and date fixes. This covers the copy with
-- duplicates removed, spelling in outlet, item_name, item_category and
-- payment_method, and order_date and order_time.

-- outlet_orders2: order_status spelling
UPDATE outlet_orders2
SET order_status = CASE
    WHEN LOWER(TRIM(order_status)) = 'served' THEN 'Served'
    WHEN LOWER(TRIM(order_status)) IN ('cancelled', 'canceled') THEN 'Cancelled'
    WHEN LOWER(TRIM(order_status)) = 'comped' THEN 'Comped'
    ELSE order_status
END;

-- outlet_orders2: restore the comped orders from the raw table (they had been changed to "completed")
UPDATE outlet_orders2
SET order_status = 'Comped'
WHERE order_id IN (
    SELECT order_id
    FROM outlet_orders
    WHERE LOWER(TRIM(order_status)) = 'comped'
);

-- outlet_orders2: rename Comped to Complimentary
UPDATE outlet_orders2
SET order_status = 'Complimentary'
WHERE LOWER(TRIM(order_status)) = 'comped';

-- outlet_orders2: add the notes column
ALTER TABLE outlet_orders2 ADD COLUMN data_issue VARCHAR(100);

-- outlet_orders2: quantity below 1 or above 50 (12 rows)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'quantity out of range set to NULL'
        ELSE CONCAT(data_issue, '; quantity out of range set to NULL')
    END,
    quantity = NULL
WHERE quantity < 1 OR quantity > 50;

-- outlet_orders2: tip_amount below 0 (3 rows)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'negative tip set to NULL'
        ELSE CONCAT(data_issue, '; negative tip set to NULL')
    END,
    tip_amount = NULL
WHERE tip_amount < 0;

-- outlet_orders2: customer_rating outside 1 to 5 (6 rows)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'customer_rating out of range'
        ELSE CONCAT(data_issue, '; customer_rating out of range')
    END,
    customer_rating = NULL
WHERE customer_rating < 1 OR customer_rating > 5;

-- outlet_orders2: orphan booking_id (booking not in bookings): flag only
-- (NULL booking_id is normal for walk-ins, so blanks are skipped)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'booking_id not in bookings'
        ELSE CONCAT(data_issue, '; booking_id not in bookings')
    END
WHERE booking_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM bookings_clean
      WHERE bookings_clean.booking_id = outlet_orders2.booking_id
  );

-- outlet_orders2: orphan server_id (staff member not in staff): flag only
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'server_id not in staff'
        ELSE CONCAT(data_issue, '; server_id not in staff')
    END
WHERE server_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM staff
      WHERE staff.staff_id = outlet_orders2.server_id
  );

-- outlet_orders2: one leftover misspelling in item_name (1 row)
UPDATE outlet_orders2
SET item_name = 'Heineken'
WHERE item_name = 'Heinekin';

-- outlet_orders2: each menu item has one normal price (28 items)
DROP TABLE IF EXISTS standard_prices;

CREATE TABLE standard_prices AS
SELECT item_name, MIN(unit_price) AS standard_price
FROM outlet_orders2
WHERE unit_price > 0
GROUP BY item_name;

-- outlet_orders2: blanks, zeros and prices 100 times too large are set
-- to the item's normal price (18 rows)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'unit_price corrected to item price'
        ELSE CONCAT(data_issue, '; unit_price corrected to item price')
    END,
    unit_price = (SELECT standard_price
                  FROM standard_prices
                  WHERE standard_prices.item_name = outlet_orders2.item_name)
WHERE unit_price IS NULL
   OR unit_price <> (SELECT standard_price
                     FROM standard_prices
                     WHERE standard_prices.item_name = outlet_orders2.item_name);

DROP TABLE IF EXISTS standard_prices;

-- outlet_orders2: recalculate totals that break the rule (20 rows)
-- rule: quantity * unit_price - discount_amount + tax_amount + tip_amount, tolerance 1
-- rows with a NULL quantity or tip are skipped automatically
-- (this runs after the quantity and tip fixes above)
UPDATE outlet_orders2
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'total_amount recalculated'
        ELSE CONCAT(data_issue, '; total_amount recalculated')
    END,
    total_amount = quantity * unit_price - discount_amount + tax_amount + tip_amount
WHERE ABS(total_amount - (quantity * unit_price - discount_amount + tax_amount + tip_amount)) > 1;


-- =====================================================================
-- 4. ROOMS  (rooms -> rooms_clean, 41 rows)
-- =====================================================================

-- rooms: remove the exact duplicate row (copy with SELECT DISTINCT)
DROP TABLE IF EXISTS rooms_clean;

CREATE TABLE rooms_clean AS
SELECT DISTINCT * FROM rooms;

-- Not included: routine text and date fixes for floor, room_type, the
-- yes/no columns (smoking_allowed, has_balcony, has_kitchenette,
-- accessible_room, minibar), status, housekeeping zone and last_renovated.

ALTER TABLE rooms_clean ADD COLUMN data_issue VARCHAR(100);

-- rooms: room 303 appears twice (room_id 13 has 14 bookings, room_id 41 has none)
-- flag only the unused copy, do not delete
UPDATE rooms_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'duplicate room_number'
        ELSE CONCAT(data_issue, '; duplicate room_number')
    END
WHERE room_id = 41;

-- rooms: max_guests of 99 and 0 (3 rows)
UPDATE rooms_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'max_guests out of range'
        ELSE CONCAT(data_issue, '; max_guests out of range')
    END,
    max_guests = NULL
WHERE max_guests < 1 OR max_guests > 10;

-- rooms: each room type has one normal rate (6 types)
DROP TABLE IF EXISTS room_standard_rates;

CREATE TABLE room_standard_rates AS
SELECT room_type, MIN(nightly_rate) AS standard_rate
FROM rooms_clean
WHERE nightly_rate > 0
GROUP BY room_type;

-- rooms: label first, then fix the rate on the same 5 rows
-- (2 blank, 1 negative, 1 zero, 1 ten times too large)
UPDATE rooms_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'nightly_rate corrected to room type rate'
        ELSE CONCAT(data_issue, '; nightly_rate corrected to room type rate')
    END
WHERE nightly_rate IS NULL
   OR nightly_rate <> (SELECT standard_rate
                       FROM room_standard_rates
                       WHERE room_standard_rates.room_type = rooms_clean.room_type);

UPDATE rooms_clean
SET nightly_rate = (SELECT standard_rate
                    FROM room_standard_rates
                    WHERE room_standard_rates.room_type = rooms_clean.room_type)
WHERE nightly_rate IS NULL
   OR nightly_rate <> (SELECT standard_rate
                       FROM room_standard_rates
                       WHERE room_standard_rates.room_type = rooms_clean.room_type);

DROP TABLE IF EXISTS room_standard_rates;


-- =====================================================================
-- 5. STAFF  (staff -> staff_clean, 40 rows)
-- =====================================================================

-- staff: remove exact duplicates (copy with SELECT DISTINCT)
DROP TABLE IF EXISTS staff_clean;

CREATE TABLE staff_clean AS
SELECT DISTINCT * FROM staff;

-- Not included: routine text and date fixes for first_name and last_name
-- capitals, department, employment_status, employment_type, shift,
-- training_completed, phone (+234 format), hire_date and last_review_date.

ALTER TABLE staff_clean ADD COLUMN data_issue VARCHAR(100);

-- staff: hire_date in the future (2 rows)
-- a fixed date is used so the result does not change when the script is run later
UPDATE staff_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'hire_date in the future'
        ELSE CONCAT(data_issue, '; hire_date in the future')
    END
WHERE hire_date > '2026-10-19';

UPDATE staff_clean
SET hire_date = NULL
WHERE data_issue LIKE '%hire_date in the future%';

-- staff: performance_rating outside 1 to 5, the 0s and the 11s (4 rows)
UPDATE staff_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'performance_rating below or above normal'
        ELSE CONCAT(data_issue, '; performance_rating below or above normal')
    END
WHERE performance_rating = 0
   OR performance_rating > 5;

UPDATE staff_clean
SET performance_rating = NULL
WHERE data_issue LIKE '%performance_rating below or above normal%';

-- staff: negative monthly_salary (1 row); blank salaries stay NULL (unknown)
UPDATE staff_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'monthly_salary negative'
        ELSE CONCAT(data_issue, '; monthly_salary negative')
    END
WHERE monthly_salary < 0;

UPDATE staff_clean
SET monthly_salary = NULL
WHERE monthly_salary < 0;

-- staff: supervisor_id points at a staff member who does not exist (ID 99, 2 rows): flag only
UPDATE staff_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'supervisor_id not in staff'
        ELSE CONCAT(data_issue, '; supervisor_id not in staff')
    END
WHERE supervisor_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM staff
      WHERE staff.staff_id = staff_clean.supervisor_id
  );

-- staff: two emails are shared by different people
-- the email pattern is first.last + staff_id, so staff 25 and 15 own theirs
-- and staff 26 and 16 do not
UPDATE staff_clean
SET data_issue = CASE
        WHEN data_issue IS NULL THEN 'email belongs to another staff member'
        ELSE CONCAT(data_issue, '; email belongs to another staff member')
    END
WHERE staff_id IN (16, 26);

UPDATE staff_clean
SET email = NULL
WHERE staff_id IN (16, 26);


-- =====================================================================
-- 6. OPTIONAL: tidy table names after cleaning (this drops the raw tables!)
--    Only run this in a database you can rebuild with lawyers_hub.sql.
-- =====================================================================
-- DROP TABLE bookings;  DROP TABLE guests;  DROP TABLE rooms;
-- DROP TABLE staff;     DROP TABLE outlet_orders;
-- RENAME TABLE bookings_clean TO bookings,
--              guests_clean TO guests,
--              rooms_clean TO rooms,
--              staff_clean TO staff,
--              outlet_orders2 TO outlet_orders;
