-- ============================================================================
-- RAILWAY SEAT RESERVATION & DYNAMIC PNR ENGINE (MySQL 8.0+)
-- Module 01: Core Database Schema Definition (DDL)
-- Normalization Standard: 3NF (Third Normal Form) Certified
-- Storage Engine: InnoDB | Character Set: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `railway_pnr_db`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `railway_pnr_db`;

-- Drop existing tables in reverse dependency order to prevent FK lock deadlocks
DROP TABLE IF EXISTS `pnr_audit_logs`;
DROP TABLE IF EXISTS `cancellations`;
DROP TABLE IF EXISTS `ticket_passengers`;
DROP TABLE IF EXISTS `pnr_bookings`;
DROP TABLE IF EXISTS `schedules`;
DROP TABLE IF EXISTS `passengers`;
DROP TABLE IF EXISTS `berths`;
DROP TABLE IF EXISTS `coaches`;
DROP TABLE IF EXISTS `train_routes`;
DROP TABLE IF EXISTS `trains`;
DROP TABLE IF EXISTS `stations`;

-- ============================================================================
-- 1. STATIONS TABLE
-- Stores individual geographical railway nodes in the nationwide transit network.
-- ============================================================================
CREATE TABLE `stations` (
    `station_id` INT AUTO_INCREMENT,
    `station_code` VARCHAR(10) NOT NULL,
    `station_name` VARCHAR(100) NOT NULL,
    `city` VARCHAR(100) NOT NULL,
    `zone` VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_stations` PRIMARY KEY (`station_id`),
    CONSTRAINT `uq_stations_code` UNIQUE (`station_code`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 2. TRAINS TABLE
-- Defines train catalog metadata and terminal journey boundaries.
-- ============================================================================
CREATE TABLE `trains` (
    `train_id` INT AUTO_INCREMENT,
    `train_number` VARCHAR(10) NOT NULL,
    `train_name` VARCHAR(120) NOT NULL,
    `train_type` ENUM('Express', 'Superfast', 'Passenger', 'Bullet') NOT NULL DEFAULT 'Express',
    `source_station_id` INT NOT NULL,
    `destination_station_id` INT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_trains` PRIMARY KEY (`train_id`),
    CONSTRAINT `uq_trains_number` UNIQUE (`train_number`),
    CONSTRAINT `fk_trains_source` FOREIGN KEY (`source_station_id`)
        REFERENCES `stations` (`station_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_trains_dest` FOREIGN KEY (`destination_station_id`)
        REFERENCES `stations` (`station_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `chk_trains_terminals_differ` CHECK (`source_station_id` <> `destination_station_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 3. TRAIN ROUTES TABLE
-- Represents intermediate operational transit stops, stop sequencing, and distances.
-- Enforces ordered traversal and zero circular loops per train instance.
-- ============================================================================
CREATE TABLE `train_routes` (
    `route_id` INT AUTO_INCREMENT,
    `train_id` INT NOT NULL,
    `station_id` INT NOT NULL,
    `stop_sequence` INT NOT NULL,
    `arrival_time` TIME NULL,
    `departure_time` TIME NULL,
    `distance_km` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_train_routes` PRIMARY KEY (`route_id`),
    CONSTRAINT `fk_routes_train` FOREIGN KEY (`train_id`)
        REFERENCES `trains` (`train_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_routes_station` FOREIGN KEY (`station_id`)
        REFERENCES `stations` (`station_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `uq_routes_train_sequence` UNIQUE (`train_id`, `stop_sequence`),
    CONSTRAINT `uq_routes_train_station` UNIQUE (`train_id`, `station_id`),
    CONSTRAINT `chk_routes_sequence_positive` CHECK (`stop_sequence` > 0),
    CONSTRAINT `chk_routes_distance_nonnegative` CHECK (`distance_km` >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 4. COACHES TABLE
-- Physical rolling stock inventory attached to trains with distinct fare classes.
-- ============================================================================
CREATE TABLE `coaches` (
    `coach_id` INT AUTO_INCREMENT,
    `train_id` INT NOT NULL,
    `coach_code` VARCHAR(10) NOT NULL,
    `coach_class` ENUM('AC1', 'AC2', 'AC3', 'Sleeper', 'Economy') NOT NULL,
    `total_seats` INT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_coaches` PRIMARY KEY (`coach_id`),
    CONSTRAINT `fk_coaches_train` FOREIGN KEY (`train_id`)
        REFERENCES `trains` (`train_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `uq_coaches_train_code` UNIQUE (`train_id`, `coach_code`),
    CONSTRAINT `chk_coaches_seats_positive` CHECK (`total_seats` > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 5. BERTHS TABLE
-- Granular atomic seating inventory within coaches categorized by ergonomics & quota.
-- ============================================================================
CREATE TABLE `berths` (
    `berth_id` INT AUTO_INCREMENT,
    `coach_id` INT NOT NULL,
    `seat_number` INT NOT NULL,
    `berth_type` ENUM('Lower', 'Middle', 'Upper', 'Side_Lower', 'Side_Upper') NOT NULL,
    `quota_type` ENUM('General', 'Ladies', 'Senior_Citizen', 'Tatkal') NOT NULL DEFAULT 'General',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_berths` PRIMARY KEY (`berth_id`),
    CONSTRAINT `fk_berths_coach` FOREIGN KEY (`coach_id`)
        REFERENCES `coaches` (`coach_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `uq_berths_coach_seat` UNIQUE (`coach_id`, `seat_number`),
    CONSTRAINT `chk_berths_seat_positive` CHECK (`seat_number` > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 6. PASSENGERS TABLE
-- Master demographic ledger of registered rail travelers.
-- ============================================================================
CREATE TABLE `passengers` (
    `passenger_id` INT AUTO_INCREMENT,
    `full_name` VARCHAR(100) NOT NULL,
    `gender` ENUM('M', 'F', 'Other') NOT NULL,
    `age` INT NOT NULL,
    `national_id` VARCHAR(50) NOT NULL,
    `phone` VARCHAR(20) NOT NULL,
    `email` VARCHAR(100) NOT NULL,
    `registered_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_passengers` PRIMARY KEY (`passenger_id`),
    CONSTRAINT `uq_passengers_national_id` UNIQUE (`national_id`),
    CONSTRAINT `uq_passengers_phone` UNIQUE (`phone`),
    CONSTRAINT `chk_passengers_age_valid` CHECK (`age` > 0 AND `age` < 120)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 7. SCHEDULES TABLE
-- Concrete dated train runs linking rolling stock to dynamic operational dates.
-- ============================================================================
CREATE TABLE `schedules` (
    `schedule_id` INT AUTO_INCREMENT,
    `train_id` INT NOT NULL,
    `journey_date` DATE NOT NULL,
    `departure_time` DATETIME NOT NULL,
    `status` ENUM('Scheduled', 'Running', 'Delayed', 'Cancelled') NOT NULL DEFAULT 'Scheduled',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_schedules` PRIMARY KEY (`schedule_id`),
    CONSTRAINT `fk_schedules_train` FOREIGN KEY (`train_id`)
        REFERENCES `trains` (`train_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `uq_schedules_train_date` UNIQUE (`train_id`, `journey_date`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 8. PNR BOOKINGS TABLE
-- Aggregated transactional booking headers identified by unique 10-character PNR.
-- ============================================================================
CREATE TABLE `pnr_bookings` (
    `pnr_id` INT AUTO_INCREMENT,
    `pnr_number` CHAR(10) NOT NULL,
    `schedule_id` INT NOT NULL,
    `booked_by_passenger_id` INT NOT NULL,
    `origin_station_id` INT NOT NULL,
    `dest_station_id` INT NOT NULL,
    `total_fare` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    `booking_status` ENUM('Confirmed', 'Partially_Confirmed', 'Waitlisted', 'Cancelled') NOT NULL DEFAULT 'Waitlisted',
    `booked_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_pnr_bookings` PRIMARY KEY (`pnr_id`),
    CONSTRAINT `uq_pnr_number` UNIQUE (`pnr_number`),
    CONSTRAINT `fk_pnr_schedule` FOREIGN KEY (`schedule_id`)
        REFERENCES `schedules` (`schedule_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_pnr_booker` FOREIGN KEY (`booked_by_passenger_id`)
        REFERENCES `passengers` (`passenger_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_pnr_origin` FOREIGN KEY (`origin_station_id`)
        REFERENCES `stations` (`station_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_pnr_dest` FOREIGN KEY (`dest_station_id`)
        REFERENCES `stations` (`station_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `chk_pnr_fare_nonnegative` CHECK (`total_fare` >= 0.00),
    CONSTRAINT `chk_pnr_stations_differ` CHECK (`origin_station_id` <> `dest_station_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 9. TICKET PASSENGERS TABLE
-- Individual passenger travel manifestations within a PNR dossier.
-- Links assigned berths, state machine flags ('CNF', 'RAC', 'WL', 'CAN'), and FIFO queue index.
-- ============================================================================
CREATE TABLE `ticket_passengers` (
    `ticket_item_id` INT AUTO_INCREMENT,
    `pnr_id` INT NOT NULL,
    `passenger_id` INT NOT NULL,
    `berth_id` INT NULL,
    `seat_status` ENUM('CNF', 'RAC', 'WL', 'CAN') NOT NULL DEFAULT 'WL',
    `waitlist_number` INT NULL,
    `fare` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `pk_ticket_passengers` PRIMARY KEY (`ticket_item_id`),
    CONSTRAINT `fk_ticket_pnr` FOREIGN KEY (`pnr_id`)
        REFERENCES `pnr_bookings` (`pnr_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_ticket_passenger` FOREIGN KEY (`passenger_id`)
        REFERENCES `passengers` (`passenger_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_ticket_berth` FOREIGN KEY (`berth_id`)
        REFERENCES `berths` (`berth_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `chk_ticket_fare_nonnegative` CHECK (`fare` >= 0.00),
    CONSTRAINT `chk_ticket_cnf_requires_berth` CHECK (
        (`seat_status` = 'CNF' AND `berth_id` IS NOT NULL) OR
        (`seat_status` IN ('RAC', 'WL', 'CAN'))
    ),
    CONSTRAINT `chk_ticket_wl_number` CHECK (
        (`seat_status` = 'WL' AND `waitlist_number` IS NOT NULL AND `waitlist_number` > 0) OR
        (`seat_status` <> 'WL')
    )
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- Performance index for high-velocity seat status and waitlist FIFO queue scanning
CREATE INDEX `idx_ticket_status_wl` ON `ticket_passengers` (`seat_status`, `waitlist_number`);
CREATE INDEX `idx_ticket_pnr_lookup` ON `ticket_passengers` (`pnr_id`, `passenger_id`);

-- ============================================================================
-- 10. CANCELLATIONS TABLE
-- Financial refund calculation ledger documenting ticket revocation penalties.
-- ============================================================================
CREATE TABLE `cancellations` (
    `cancellation_id` INT AUTO_INCREMENT,
    `ticket_item_id` INT NOT NULL,
    `pnr_id` INT NOT NULL,
    `refund_amount` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    `cancellation_charge` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    `cancelled_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_cancellations` PRIMARY KEY (`cancellation_id`),
    CONSTRAINT `uq_cancellations_ticket` UNIQUE (`ticket_item_id`),
    CONSTRAINT `fk_cancellations_ticket` FOREIGN KEY (`ticket_item_id`)
        REFERENCES `ticket_passengers` (`ticket_item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_cancellations_pnr` FOREIGN KEY (`pnr_id`)
        REFERENCES `pnr_bookings` (`pnr_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `chk_cancellations_refund_positive` CHECK (`refund_amount` >= 0.00),
    CONSTRAINT `chk_cancellations_charge_positive` CHECK (`cancellation_charge` >= 0.00)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ============================================================================
-- 11. PNR AUDIT LOGS TABLE
-- Immutable compliance ledger capturing state-machine transitions and berth reallocations.
-- ============================================================================
CREATE TABLE `pnr_audit_logs` (
    `log_id` INT AUTO_INCREMENT,
    `pnr_id` INT NOT NULL,
    `ticket_item_id` INT NOT NULL,
    `old_seat_status` VARCHAR(20) NOT NULL,
    `new_seat_status` VARCHAR(20) NOT NULL,
    `berth_assigned` INT NULL,
    `reason` VARCHAR(255) NOT NULL,
    `logged_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_pnr_audit_logs` PRIMARY KEY (`log_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE INDEX `idx_audit_pnr_ticket` ON `pnr_audit_logs` (`pnr_id`, `ticket_item_id`);
CREATE INDEX `idx_audit_timestamp` ON `pnr_audit_logs` (`logged_at`);
