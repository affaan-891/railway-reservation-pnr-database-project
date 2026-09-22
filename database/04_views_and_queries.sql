-- ============================================================================
-- RAILWAY SEAT RESERVATION & DYNAMIC PNR ENGINE (MySQL 8.0+)
-- Module 04: Analytical Views & Advanced Viva Defense Queries
-- Engine: MySQL 8.0+
-- ============================================================================

USE `railway_pnr_db`;

DROP VIEW IF EXISTS `vw_train_pnr_chart`;
DROP VIEW IF EXISTS `vw_route_revenue_analysis`;

-- ============================================================================
-- VIEW 1: vw_train_pnr_chart
-- Real-time Operational Train Reservation & Charting Manifest.
-- Displays granular passenger boarding list: coach, seat, demographic, and state.
-- ============================================================================
CREATE VIEW `vw_train_pnr_chart` AS
SELECT
    s.schedule_id,
    t.train_number,
    t.train_name,
    s.journey_date,
    s.departure_time,
    pb.pnr_number,
    p.full_name AS passenger_name,
    p.age,
    p.gender,
    COALESCE(c.coach_code, 'UNASSIGNED') AS coach_code,
    COALESCE(c.coach_class, 'WL') AS coach_class,
    COALESCE(b.seat_number, 0) AS seat_number,
    COALESCE(b.berth_type, 'N/A') AS berth_type,
    COALESCE(b.quota_type, 'General') AS quota_type,
    tp.seat_status,
    tp.waitlist_number,
    st_orig.station_code AS origin_station,
    st_dest.station_code AS destination_station,
    tp.fare
FROM `ticket_passengers` tp
JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
JOIN `schedules` s ON pb.schedule_id = s.schedule_id
JOIN `trains` t ON s.train_id = t.train_id
JOIN `passengers` p ON tp.passenger_id = p.passenger_id
JOIN `stations` st_orig ON pb.origin_station_id = st_orig.station_id
JOIN `stations` st_dest ON pb.dest_station_id = st_dest.station_id
LEFT JOIN `berths` b ON tp.berth_id = b.berth_id
LEFT JOIN `coaches` c ON b.coach_id = c.coach_id;

-- ============================================================================
-- VIEW 2: vw_route_revenue_analysis
-- Financial Performance Ledger per Train Route.
-- Aggregates gross ticket sales, cancellation charges forfeited, and net earnings.
-- ============================================================================
CREATE VIEW `vw_route_revenue_analysis` AS
SELECT
    t.train_id,
    t.train_number,
    t.train_name,
    t.train_type,
    s_orig.station_code AS origin_code,
    s_dest.station_code AS dest_code,
    COUNT(DISTINCT s.schedule_id) AS total_runs_scheduled,
    COUNT(DISTINCT tp.ticket_item_id) AS total_tickets_booked,
    SUM(CASE WHEN tp.seat_status = 'CNF' THEN 1 ELSE 0 END) AS confirmed_passengers,
    SUM(CASE WHEN tp.seat_status = 'WL' THEN 1 ELSE 0 END) AS waitlisted_passengers,
    SUM(CASE WHEN tp.seat_status = 'CAN' THEN 1 ELSE 0 END) AS cancelled_passengers,
    COALESCE(SUM(tp.fare), 0.00) AS gross_booking_revenue,
    COALESCE(SUM(cn.cancellation_charge), 0.00) AS cancellation_penalties_retained,
    COALESCE(SUM(cn.refund_amount), 0.00) AS total_refunds_disbursed,
    COALESCE(SUM(CASE WHEN tp.seat_status <> 'CAN' THEN tp.fare ELSE 0.00 END) +
             SUM(COALESCE(cn.cancellation_charge, 0.00)), 0.00) AS net_revenue
FROM `trains` t
JOIN `stations` s_orig ON t.source_station_id = s_orig.station_id
JOIN `stations` s_dest ON t.destination_station_id = s_dest.station_id
LEFT JOIN `schedules` s ON t.train_id = s.train_id
LEFT JOIN `pnr_bookings` pb ON s.schedule_id = pb.schedule_id
LEFT JOIN `ticket_passengers` tp ON pb.pnr_id = tp.pnr_id
LEFT JOIN `cancellations` cn ON tp.ticket_item_id = cn.ticket_item_id
GROUP BY
    t.train_id, t.train_number, t.train_name, t.train_type,
    s_orig.station_code, s_dest.station_code;

-- ============================================================================
-- COMPLEX VIVA QUERY 1: Aggregation with INNER/LEFT JOIN and HAVING clause
-- Target: Identify schedules operating near or above 75% physical capacity.
-- Evaluator Focus: Multi-table aggregation, NULL handling, and HAVING filter on derived expressions.
-- ============================================================================
SELECT
    s.schedule_id,
    t.train_number,
    t.train_name,
    s.journey_date,
    COALESCE(cap.total_capacity, 0) AS total_train_capacity,
    COUNT(CASE WHEN tp.seat_status = 'CNF' THEN 1 END) AS confirmed_bookings,
    COUNT(CASE WHEN tp.seat_status = 'WL' THEN 1 END) AS waitlist_queue_length,
    ROUND((COUNT(CASE WHEN tp.seat_status = 'CNF' THEN 1 END) / NULLIF(cap.total_capacity, 0)) * 100.0, 2) AS occupancy_percentage
FROM `schedules` s
JOIN `trains` t ON s.train_id = t.train_id
LEFT JOIN (
    SELECT train_id, SUM(total_seats) AS total_capacity
    FROM `coaches`
    GROUP BY train_id
) cap ON t.train_id = cap.train_id
LEFT JOIN `pnr_bookings` pb ON s.schedule_id = pb.schedule_id
LEFT JOIN `ticket_passengers` tp ON pb.pnr_id = tp.pnr_id
GROUP BY
    s.schedule_id, t.train_number, t.train_name, s.journey_date, cap.total_capacity
HAVING occupancy_percentage >= 70.00 OR waitlist_queue_length > 0
ORDER BY occupancy_percentage DESC;

-- ============================================================================
-- COMPLEX VIVA QUERY 2: Anti-Join using NOT EXISTS
-- Target: Find physical berths in active coaches that have NEVER been booked
-- across any upcoming schedule (unutilized physical capacity).
-- Evaluator Focus: Subquery un-nesting, NOT EXISTS vs NOT IN NULL pitfalls.
-- ============================================================================
SELECT
    t.train_number,
    t.train_name,
    c.coach_code,
    c.coach_class,
    b.seat_number,
    b.berth_type,
    b.quota_type
FROM `berths` b
JOIN `coaches` c ON b.coach_id = c.coach_id
JOIN `trains` t ON c.train_id = t.train_id
WHERE NOT EXISTS (
    SELECT 1
    FROM `ticket_passengers` tp
    JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
    JOIN `schedules` s ON pb.schedule_id = s.schedule_id
    WHERE tp.berth_id = b.berth_id
      AND tp.seat_status = 'CNF'
      AND s.journey_date >= CURRENT_DATE
)
ORDER BY t.train_number, c.coach_code, b.seat_number;

-- ============================================================================
-- COMPLEX VIVA QUERY 3: Correlated Subquery
-- Target: Identify frequent passengers whose booked journey fares exceed the
-- average ticket fare for their respective train journey.
-- Evaluator Focus: Outer query reference in subquery scope, row-by-row predicate evaluation.
-- ============================================================================
SELECT
    p.passenger_id,
    p.full_name,
    pb.pnr_number,
    t.train_number,
    t.train_name,
    tp.fare AS passenger_fare,
    (
        SELECT ROUND(AVG(tp_inner.fare), 2)
        FROM `ticket_passengers` tp_inner
        JOIN `pnr_bookings` pb_inner ON tp_inner.pnr_id = pb_inner.pnr_id
        WHERE pb_inner.schedule_id = pb.schedule_id
    ) AS schedule_average_fare
FROM `passengers` p
JOIN `ticket_passengers` tp ON p.passenger_id = tp.passenger_id
JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
JOIN `schedules` s ON pb.schedule_id = s.schedule_id
JOIN `trains` t ON s.train_id = t.train_id
WHERE tp.fare > (
    SELECT AVG(tp_inner.fare)
    FROM `ticket_passengers` tp_inner
    JOIN `pnr_bookings` pb_inner ON tp_inner.pnr_id = pb_inner.pnr_id
    WHERE pb_inner.schedule_id = pb.schedule_id
)
ORDER BY (tp.fare - schedule_average_fare) DESC;

-- ============================================================================
-- COMPLEX VIVA QUERY 4: Analytical Window Function DENSE_RANK() & OVER (PARTITION BY)
-- Target: Rank trains by total fare revenue generated within each train_type category.
-- Evaluator Focus: Partitioning, ranking functions, window execution in MySQL 8.0+.
-- ============================================================================
SELECT
    t.train_type,
    t.train_number,
    t.train_name,
    COALESCE(SUM(tp.fare), 0.00) AS total_gross_revenue,
    DENSE_RANK() OVER (
        PARTITION BY t.train_type
        ORDER BY COALESCE(SUM(tp.fare), 0.00) DESC
    ) AS revenue_rank_in_category
FROM `trains` t
LEFT JOIN `schedules` s ON t.train_id = s.train_id
LEFT JOIN `pnr_bookings` pb ON s.schedule_id = pb.schedule_id
LEFT JOIN `ticket_passengers` tp ON pb.pnr_id = tp.pnr_id
GROUP BY t.train_type, t.train_id, t.train_number, t.train_name
ORDER BY t.train_type, revenue_rank_in_category;

-- ============================================================================
-- COMPLEX VIVA QUERY 5: Query Execution Plan (EXPLAIN ANALYZE) on Indexed Waitlist
-- Target: Evaluate index scan efficiency on composite index idx_ticket_status_wl.
-- Evaluator Focus: Cost estimation, index condition pushdown, sequential vs index lookup.
-- ============================================================================
EXPLAIN ANALYZE
SELECT
    tp.ticket_item_id,
    pb.pnr_number,
    p.full_name,
    tp.seat_status,
    tp.waitlist_number,
    s.journey_date
FROM `ticket_passengers` tp
JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
JOIN `schedules` s ON pb.schedule_id = s.schedule_id
JOIN `passengers` p ON tp.passenger_id = p.passenger_id
WHERE pb.schedule_id = 1
  AND tp.seat_status = 'WL'
ORDER BY tp.waitlist_number ASC;
