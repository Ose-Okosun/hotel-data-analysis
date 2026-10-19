-- =====================================================================
-- 02_analysis.sql
-- Database: lawyers_hub (MySQL)
-- Run AFTER 01_cleaning.sql.
--
-- Table names below (bookings, guests, rooms, staff, outlet_orders) are
-- the cleaned tables. If your cleaned tables still carry their working
-- names, read bookings_clean, guests_clean, rooms_clean, staff_clean and
-- outlet_orders2 instead.
--
-- Each query starts with the question as a hotel manager would ask it.
-- Flagged rows (see the data_issue column) are handled in each query:
-- an inner JOIN drops orphan IDs, and the orphan booking_id 9999 is
-- excluded on purpose where it would otherwise distort a result.
-- =====================================================================

USE lawyers_hub;


-- =====================================================================
-- A. REVENUE
-- =====================================================================

-- Q1. The manager asks: "Which booking channel brings in the most money,
--     and how many bookings does each channel have?"
-- Finding: Direct earns the most (about 62.8 million from 132 bookings),
-- roughly double the next channel, Booking site.
SELECT booking_channel,
       COUNT(*) AS total_bookings,
       SUM(total_amount) AS total_revenue
FROM bookings
WHERE total_amount IS NOT NULL
GROUP BY booking_channel
ORDER BY total_revenue DESC;


-- Q2. The manager asks: "Which room type earns the most, and how many
--     bookings does each type have?"
-- The plain JOIN leaves out the 4 bookings whose room_id does not exist.
-- Finding: Suite earns the most (about 48.1 million from 76 bookings).
-- Presidential is second (about 43.3 million) from only 27 bookings.
SELECT room_type,
       COUNT(*) AS total_bookings,
       SUM(total_amount) AS total_revenue
FROM rooms
JOIN bookings ON rooms.room_id = bookings.room_id
WHERE total_amount IS NOT NULL
GROUP BY room_type
ORDER BY total_revenue DESC;


-- Q3. The manager asks: "Which outlet earns the most from orders that
--     were actually served, and how many served orders does each have?"
-- Complimentary orders are kept separate from Served.
SELECT outlet,
       SUM(total_amount) AS total_revenue,
       COUNT(*) AS total_served
FROM outlet_orders
WHERE order_status = 'Served'
GROUP BY outlet
ORDER BY total_revenue DESC;


-- =====================================================================
-- B. ROOMS AND GUESTS
-- =====================================================================

-- Q4. The manager asks: "Which rooms have never been booked?"
-- Finding: only room_id 41, the duplicate copy of room 303 that was
-- flagged in cleaning. Every real room has been booked at least once.
SELECT room_id, room_number, room_type
FROM rooms
WHERE room_id IS NOT NULL
  AND NOT EXISTS (SELECT 1
                  FROM bookings
                  WHERE bookings.room_id = rooms.room_id);


-- Q5. The manager asks: "Which guests have never made a booking?"
-- Finding: 11 guests.
SELECT guest_id, first_name, last_name
FROM guests
WHERE guests.guest_id IS NOT NULL
  AND NOT EXISTS (SELECT 1
                  FROM bookings
                  WHERE bookings.guest_id = guests.guest_id);


-- Q6. The manager asks: "Who are our top 3 spending guests in each
--     loyalty tier?"
-- Step 1 (inside the brackets): add up each guest's spending and rank
-- guests within their tier. Step 2: keep only ranks 1 to 3.
-- Finding: tier does not predict spending. The top Silver guest spent
-- more than the top Gold and Platinum guests.
WITH guest_revenue_ranking AS (
    SELECT loyalty_tier, bookings.guest_id, first_name, last_name,
           SUM(total_amount) AS total_revenue,
           RANK() OVER (PARTITION BY loyalty_tier ORDER BY SUM(total_amount) DESC) AS ranking
    FROM bookings
    JOIN guests ON bookings.guest_id = guests.guest_id
    WHERE total_amount IS NOT NULL
    GROUP BY loyalty_tier, bookings.guest_id, first_name, last_name
)
SELECT loyalty_tier, guest_id, first_name, last_name, total_revenue, ranking
FROM guest_revenue_ranking
WHERE ranking <= 3
ORDER BY loyalty_tier, ranking;


-- Q7. The manager asks: "Which bookings were made by a guest who had
--     already stayed with us within the previous 30 days?"
-- LAG brings in the same guest's previous check-in date. A guest's first
-- booking has no previous one, so it drops out of the filter.
WITH booking_gaps AS (
    SELECT guest_id, booking_id, check_in,
           LAG(check_in) OVER (PARTITION BY guest_id ORDER BY check_in) AS previous_check_in
    FROM bookings
    WHERE guest_id IS NOT NULL
      AND check_in IS NOT NULL
)
SELECT guest_id, booking_id, check_in, previous_check_in,
       DATEDIFF(check_in, previous_check_in) AS days_since_previous
FROM booking_gaps
WHERE DATEDIFF(check_in, previous_check_in) <= 30
ORDER BY guest_id, check_in;


-- Q8. The manager asks: "Which bookings were worth more than the same
--     guest's previous booking, and by how much?"
WITH previous_bookings AS (
    SELECT guest_id, booking_id, check_in, total_amount,
           LAG(total_amount) OVER (PARTITION BY guest_id ORDER BY check_in, booking_id) AS previous_amount
    FROM bookings
    WHERE guest_id IS NOT NULL
      AND check_in IS NOT NULL
      AND total_amount IS NOT NULL
)
SELECT guest_id, booking_id, check_in, total_amount, previous_amount,
       total_amount - previous_amount AS increase
FROM previous_bookings
WHERE total_amount > previous_amount
ORDER BY guest_id, check_in;


-- =====================================================================
-- C. BOOKING PATTERNS
-- =====================================================================

-- Q9. The manager asks: "How long do guests stay, and does a longer stay
--     earn more per booking?"
-- Stays are sorted into Short (1 to 2 nights), Medium (3 to 5) and
-- Long (6 or more).
SELECT CASE
           WHEN nights BETWEEN 1 AND 2 THEN 'Short'
           WHEN nights BETWEEN 3 AND 5 THEN 'Medium'
           ELSE 'Long'
       END AS stay_length,
       COUNT(*) AS total_bookings,
       AVG(total_amount) AS average_amount
FROM bookings
WHERE total_amount IS NOT NULL
  AND nights IS NOT NULL
GROUP BY stay_length
ORDER BY average_amount DESC;


-- Q10. The manager asks: "Do guests who book far in advance spend more,
--      and do they stay longer?"
-- Booking types by days between booking and arrival: last_minute (0 to 7),
-- planned (8 to 30), early (31 or more).
-- Finding: early bookings are worth about 13% more per booking
-- (about 464,000 against about 410,000), with the same stay of about 4 nights.
SELECT CASE
           WHEN DATEDIFF(check_in, booking_date) BETWEEN 0 AND 7 THEN 'last_minute'
           WHEN DATEDIFF(check_in, booking_date) BETWEEN 8 AND 30 THEN 'planned'
           ELSE 'early'
       END AS booking_type,
       COUNT(*) AS total_bookings,
       AVG(total_amount) AS average_amount,
       AVG(nights) AS average_nights
FROM bookings
WHERE total_amount IS NOT NULL
GROUP BY booking_type
ORDER BY average_amount DESC;


-- Q11. The manager asks: "How many of our bookings ended in each status:
--      completed, confirmed, cancelled or no-show?"
-- Finding: 337 completed, 68 confirmed, 31 cancelled and 14 no-shows.
SELECT booking_status,
       COUNT(*) AS total_bookings
FROM bookings
GROUP BY booking_status
ORDER BY total_bookings DESC;


-- Q12. The manager asks: "Which booking channel loses the most bookings
--      to cancellation, as a share of the bookings it brings in?"
-- SUM(CASE ...) counts only the cancelled bookings inside each channel.
-- Finding: Direct has the most cancellations (10), but Expedia (12.5%)
-- and Agent (12%) lose a bigger share than Direct (7.6%). The numbers
-- are small, so treat this as a pattern to watch.
SELECT booking_channel,
       COUNT(*) AS total_bookings,
       SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_bookings,
       ROUND(SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS cancellation_rate
FROM bookings
GROUP BY booking_channel
ORDER BY cancellation_rate DESC;


-- =====================================================================
-- D. OUTLETS AND STAFF
-- =====================================================================

-- Q13. The manager asks: "Which outlet loses the most orders to
--      cancellation, as a share of the orders it receives?"
SELECT outlet,
       COUNT(*) AS total_orders,
       SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders,
       ROUND(SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS cancellation_rate
FROM outlet_orders
GROUP BY outlet
ORDER BY cancellation_rate DESC;


-- Q14. The manager asks: "Which orders were bigger than the previous
--      order on the same booking, and by how much?"
-- The orphan booking_id 9999 (flagged in cleaning) is excluded, because
-- it is not a real booking.
WITH order_comparison AS (
    SELECT booking_id, order_id, order_date, total_amount,
           LAG(total_amount) OVER (PARTITION BY booking_id ORDER BY order_date, order_id) AS previous_amount
    FROM outlet_orders
    WHERE booking_id IS NOT NULL
      AND booking_id <> 9999
      AND total_amount IS NOT NULL
)
SELECT booking_id, order_id, order_date, total_amount, previous_amount,
       total_amount - previous_amount AS increase
FROM order_comparison
WHERE total_amount > previous_amount
ORDER BY booking_id, order_id;


-- Q15. The manager asks: "Which bookings had more than 3 served outlet
--      orders, and how much did each spend at the outlets compared with
--      the room?"
-- The JOIN also leaves out the orphan booking_id 9999.
SELECT bookings.booking_id,
       COUNT(outlet_orders.order_id) AS served_orders,
       SUM(outlet_orders.total_amount) AS outlet_spend,
       bookings.total_amount AS room_total
FROM bookings
JOIN outlet_orders
    ON bookings.booking_id = outlet_orders.booking_id
WHERE outlet_orders.order_status = 'Served'
  AND outlet_orders.booking_id <> 9999
GROUP BY bookings.booking_id, bookings.total_amount
HAVING COUNT(outlet_orders.order_id) > 3
ORDER BY outlet_spend DESC;


-- Q16. The manager asks: "How many bookings did each staff member
--      handle? Include staff who handled none."
-- LEFT JOIN keeps every staff member. COUNT(booking_id) gives 0, not 1,
-- for staff with no bookings.
SELECT staff.staff_id, first_name, last_name, job_title,
       COUNT(booking_id) AS bookings_handled
FROM staff
LEFT JOIN bookings ON staff.staff_id = bookings.assigned_staff_id
GROUP BY staff.staff_id, first_name, last_name, job_title
ORDER BY bookings_handled DESC, staff.staff_id;


-- Q17. The manager asks: "Which staff members brought in the most money
--      from the orders they served?"
-- Orders with no real server (the flagged ID 88, or none) are left out.
SELECT staff.staff_id, first_name, last_name,
       COUNT(*) AS served_orders,
       ROUND(SUM(total_amount), 1) AS total_sales
FROM outlet_orders
JOIN staff ON staff.staff_id = outlet_orders.server_id
WHERE order_status = 'Served'
GROUP BY staff.staff_id, first_name, last_name
ORDER BY total_sales DESC;


-- Q18. The manager asks: "For our top 5 sellers, which outlet do their
--      orders come from?"
-- Grouping by staff and outlet gives one row per person per outlet, and
-- LIMIT 5 keeps the top 5 rows.
-- Finding: the Spa has only 38 served orders, over half from one staff
-- member, but its orders are worth far more each (about 55,000 against
-- 9,000 to 22,000 in other outlets). Worth testing, not yet proven.
SELECT staff.staff_id, first_name, last_name, outlet,
       COUNT(*) AS served_orders,
       ROUND(SUM(total_amount), 1) AS total_sales
FROM outlet_orders
JOIN staff ON staff.staff_id = outlet_orders.server_id
WHERE order_status = 'Served'
GROUP BY staff.staff_id, first_name, last_name, outlet
ORDER BY total_sales DESC
LIMIT 5;
