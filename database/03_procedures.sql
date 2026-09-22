-- ============================================================================
-- RAILWAY SEAT RESERVATION & DYNAMIC PNR ENGINE (MySQL 8.0+)
-- Module 03: Transactional Procedures, ACID Isolation & Analytics Engine
-- Engine: MySQL 8.0+ | Delimiter: //
-- ============================================================================

USE `railway_pnr_db`;

DROP PROCEDURE IF EXISTS `sp_book_railway_ticket`;
DROP PROCEDURE IF EXISTS `sp_process_ticket_cancellation`;
DROP FUNCTION IF EXISTS `fn_calculate_train_occupancy_ratio`;

DELIMITER //

-- ============================================================================
-- 1. STORED FUNCTION: fn_calculate_train_occupancy_ratio
-- Computes the percentage of physical seats currently confirmed for a given train run.
-- Returns DECIMAL(5, 2) e.g., 87.50 represents 87.50% capacity booked.
-- ============================================================================
CREATE FUNCTION `fn_calculate_train_occupancy_ratio`(
    p_schedule_id INT
)
RETURNS DECIMAL(5, 2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_train_id INT;
    DECLARE v_total_capacity INT DEFAULT 0;
    DECLARE v_booked_seats INT DEFAULT 0;
    DECLARE v_occupancy_ratio DECIMAL(5, 2) DEFAULT 0.00;

    -- Fetch train_id associated with this schedule
    SELECT `train_id` INTO v_train_id
    FROM `schedules`
    WHERE `schedule_id` = p_schedule_id;

    IF v_train_id IS NULL THEN
        RETURN 0.00;
    END IF;

    -- Aggregate total capacity across all operational coaches on this train
    SELECT COALESCE(SUM(`total_seats`), 0) INTO v_total_capacity
    FROM `coaches`
    WHERE `train_id` = v_train_id;

    -- Count active confirmed passengers holding physical berths on this schedule
    SELECT COUNT(*) INTO v_booked_seats
    FROM `ticket_passengers` tp
    JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
    WHERE pb.schedule_id = p_schedule_id
      AND tp.seat_status = 'CNF';

    IF v_total_capacity > 0 THEN
        SET v_occupancy_ratio = ROUND((v_booked_seats / v_total_capacity) * 100.0, 2);
    ELSE
        SET v_occupancy_ratio = 0.00;
    END IF;

    RETURN v_occupancy_ratio;
END //

-- ============================================================================
-- 2. STORED PROCEDURE: sp_book_railway_ticket
-- Implements Pessimistic Concurrency Locking (SELECT ... FOR UPDATE) inside an
-- explicit ACID transaction to prevent race conditions during high-volume seat allocations.
--
-- Logic:
-- 1. Acquires row-level pessimistic locks on available berths in requested coach class.
-- 2. If preferred berth type is vacant, claims it immediately.
-- 3. If preferred berth type is occupied, claims any vacant berth in that class.
-- 4. If coach class is at 100% capacity, dynamically assigns next FIFO Waitlist position (WL #N).
-- 5. Generates an authentic 10-digit PNR code, calculates tiered distance fare,
--    and inserts records into pnr_bookings and ticket_passengers.
-- ============================================================================
CREATE PROCEDURE `sp_book_railway_ticket`(
    IN  p_schedule_id        INT,
    IN  p_booker_id          INT,
    IN  p_passenger_id       INT,
    IN  p_origin_station     INT,
    IN  p_dest_station       INT,
    IN  p_preferred_class    VARCHAR(10),
    IN  p_preferred_berth    VARCHAR(20),
    OUT p_pnr_number         CHAR(10),
    OUT p_seat_status        VARCHAR(10)
)
proc_label: BEGIN
    -- SQL Exception Handler: Guarantees strict Atomicity by rolling back on any failure
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_pnr_number = NULL;
        SET p_seat_status = 'ERROR';
        RESIGNAL;
    END;

    -- Local working variables
    DECLARE v_train_id INT;
    DECLARE v_journey_date DATE;
    DECLARE v_allocated_berth_id INT DEFAULT NULL;
    DECLARE v_allocated_status VARCHAR(10) DEFAULT 'WL';
    DECLARE v_next_wl_num INT DEFAULT NULL;
    DECLARE v_distance INT DEFAULT 0;
    DECLARE v_base_rate DECIMAL(6, 2) DEFAULT 1.50;
    DECLARE v_class_multiplier DECIMAL(4, 2) DEFAULT 1.00;
    DECLARE v_calculated_fare DECIMAL(8, 2) DEFAULT 0.00;
    DECLARE v_new_pnr_id INT;
    DECLARE v_new_ticket_id INT;
    DECLARE v_candidate_pnr CHAR(10);
    DECLARE v_pnr_exists INT DEFAULT 1;

    -- Start Explicit ACID Transaction
    START TRANSACTION;

    -- Verify valid schedule
    SELECT `train_id`, `journey_date`
    INTO v_train_id, v_journey_date
    FROM `schedules`
    WHERE `schedule_id` = p_schedule_id
    FOR SHARE;

    IF v_train_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Validation Failed: Train schedule does not exist.';
    END IF;

    -- Calculate travel distance between origin and destination stations along the train route
    SELECT COALESCE(ABS(MAX(CASE WHEN station_id = p_dest_station THEN distance_km END) -
                        MAX(CASE WHEN station_id = p_origin_station THEN distance_km END)), 350)
    INTO v_distance
    FROM `train_routes`
    WHERE `train_id` = v_train_id
      AND `station_id` IN (p_origin_station, p_dest_station);

    IF v_distance <= 0 THEN
        SET v_distance = 450; -- Default sensible transit distance
    END IF;

    -- Set class multipliers for fare calculation
    IF p_preferred_class = 'AC1' THEN
        SET v_class_multiplier = 3.50;
    ELSEIF p_preferred_class = 'AC2' THEN
        SET v_class_multiplier = 2.40;
    ELSEIF p_preferred_class = 'AC3' THEN
        SET v_class_multiplier = 1.70;
    ELSEIF p_preferred_class = 'Sleeper' THEN
        SET v_class_multiplier = 1.00;
    ELSE
        SET v_class_multiplier = 0.75; -- Economy
    END IF;

    SET v_calculated_fare = ROUND(v_distance * v_base_rate * v_class_multiplier, 2);

    -- STEP 1: Attempt Preferred Berth Allocation using PESSIMISTIC LOCKING
    SELECT b.berth_id INTO v_allocated_berth_id
    FROM `berths` b
    JOIN `coaches` c ON b.coach_id = c.coach_id
    WHERE c.train_id = v_train_id
      AND c.coach_class = p_preferred_class
      AND b.berth_type = p_preferred_berth
      AND b.berth_id NOT IN (
          SELECT tp.berth_id
          FROM `ticket_passengers` tp
          JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
          WHERE pb.schedule_id = p_schedule_id
            AND tp.seat_status = 'CNF'
            AND tp.berth_id IS NOT NULL
      )
    ORDER BY b.berth_id ASC
    LIMIT 1
    FOR UPDATE;

    -- STEP 2: Fallback to any vacant berth within the requested coach class
    IF v_allocated_berth_id IS NULL THEN
        SELECT b.berth_id INTO v_allocated_berth_id
        FROM `berths` b
        JOIN `coaches` c ON b.coach_id = c.coach_id
        WHERE c.train_id = v_train_id
          AND c.coach_class = p_preferred_class
          AND b.berth_id NOT IN (
              SELECT tp.berth_id
              FROM `ticket_passengers` tp
              JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
              WHERE pb.schedule_id = p_schedule_id
                AND tp.seat_status = 'CNF'
                AND tp.berth_id IS NOT NULL
          )
        ORDER BY b.berth_id ASC
        LIMIT 1
        FOR UPDATE;
    END IF;

    -- STEP 3: Assign Confirmation Status or FIFO Waitlist
    IF v_allocated_berth_id IS NOT NULL THEN
        SET v_allocated_status = 'CNF';
        SET v_next_wl_num = NULL;
    ELSE
        -- Train class is fully booked. Calculate Next FIFO Waitlist Position
        SET v_allocated_status = 'WL';
        SET v_allocated_berth_id = NULL;

        SELECT COALESCE(MAX(tp.waitlist_number), 0) + 1 INTO v_next_wl_num
        FROM `ticket_passengers` tp
        JOIN `pnr_bookings` pb ON tp.pnr_id = pb.pnr_id
        WHERE pb.schedule_id = p_schedule_id
          AND tp.seat_status = 'WL';
    END IF;

    -- Generate a collision-free 10-digit numeric PNR
    pnr_gen_loop: WHILE v_pnr_exists > 0 DO
        SET v_candidate_pnr = LPAD(FLOOR(1000000000 + (RAND() * 9000000000)), 10, '0');
        SELECT COUNT(*) INTO v_pnr_exists FROM `pnr_bookings` WHERE `pnr_number` = v_candidate_pnr;
    END WHILE;

    -- Insert Booking Header
    INSERT INTO `pnr_bookings` (
        `pnr_number`, `schedule_id`, `booked_by_passenger_id`,
        `origin_station_id`, `dest_station_id`, `total_fare`, `booking_status`
    ) VALUES (
        v_candidate_pnr,
        p_schedule_id,
        p_booker_id,
        p_origin_station,
        p_dest_station,
        v_calculated_fare,
        CASE WHEN v_allocated_status = 'CNF' THEN 'Confirmed' ELSE 'Waitlisted' END
    );

    SET v_new_pnr_id = LAST_INSERT_ID();

    -- Insert Passenger Travel Item
    INSERT INTO `ticket_passengers` (
        `pnr_id`, `passenger_id`, `berth_id`, `seat_status`, `waitlist_number`, `fare`
    ) VALUES (
        v_new_pnr_id,
        p_passenger_id,
        v_allocated_berth_id,
        v_allocated_status,
        v_next_wl_num,
        v_calculated_fare
    );

    SET v_new_ticket_id = LAST_INSERT_ID();

    -- Log transaction into Audit Ledger
    INSERT INTO `pnr_audit_logs` (
        `pnr_id`, `ticket_item_id`, `old_seat_status`, `new_seat_status`, `berth_assigned`, `reason`
    ) VALUES (
        v_new_pnr_id,
        v_new_ticket_id,
        'NEW',
        v_allocated_status,
        v_allocated_berth_id,
        CASE
            WHEN v_allocated_status = 'CNF' THEN 'Initial booking: Confirmed berth allocated'
            ELSE CONCAT('Initial booking: Placed in waitlist queue position #', v_next_wl_num)
        END
    );

    -- Commit ACID Transaction
    COMMIT;

    -- Set Output Return Parameters
    SET p_pnr_number = v_candidate_pnr;
    SET p_seat_status = v_allocated_status;
END //

-- ============================================================================
-- 3. STORED PROCEDURE: sp_process_ticket_cancellation
-- Handles safe, transactional ticket cancellations.
-- Triggers `trg_calculate_cancellation_penalty` and
-- `trg_auto_promote_waitlist_on_cancellation` upon inserting into `cancellations`.
-- ============================================================================
CREATE PROCEDURE `sp_process_ticket_cancellation`(
    IN  p_ticket_item_id INT,
    OUT p_refund         DECIMAL(8, 2)
)
proc_cancel: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_refund = 0.00;
        RESIGNAL;
    END;

    DECLARE v_pnr_id INT;
    DECLARE v_current_status VARCHAR(10);
    DECLARE v_fare DECIMAL(8, 2);
    DECLARE v_new_cancel_id INT;

    START TRANSACTION;

    -- Lock ticket row for update
    SELECT `pnr_id`, `seat_status`, `fare`
    INTO v_pnr_id, v_current_status, v_fare
    FROM `ticket_passengers`
    WHERE `ticket_item_id` = p_ticket_item_id
    FOR UPDATE;

    IF v_pnr_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cancellation Failed: Ticket item does not exist.';
    END IF;

    IF v_current_status = 'CAN' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cancellation Failed: Ticket is already marked as Cancelled.';
    END IF;

    -- Insert into cancellations. Triggers will automatically calculate penalty
    -- and promote the next waitlisted passenger.
    INSERT INTO `cancellations` (`ticket_item_id`, `pnr_id`, `refund_amount`, `cancellation_charge`)
    VALUES (p_ticket_item_id, v_pnr_id, 0.00, 0.00);

    SET v_new_cancel_id = LAST_INSERT_ID();

    -- Retrieve calculated refund from cancellations
    SELECT `refund_amount` INTO p_refund
    FROM `cancellations`
    WHERE `cancellation_id` = v_new_cancel_id;

    -- Update parent PNR status if all associated tickets have been cancelled
    IF NOT EXISTS (
        SELECT 1 FROM `ticket_passengers`
        WHERE `pnr_id` = v_pnr_id AND `seat_status` <> 'CAN'
    ) THEN
        UPDATE `pnr_bookings`
        SET `booking_status` = 'Cancelled'
        WHERE `pnr_id` = v_pnr_id;
    END IF;

    COMMIT;
END //

DELIMITER ;
