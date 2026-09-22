-- ============================================================================
-- RAILWAY SEAT RESERVATION & DYNAMIC PNR ENGINE (MySQL 8.0+)
-- Module 05: Realistic Production-Grade Seed Data (DML)
-- Engine: MySQL 8.0+
-- ============================================================================

USE `railway_pnr_db`;

-- Disable foreign key checks during batch population to ensure clean sequential load
SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE `pnr_audit_logs`;
TRUNCATE TABLE `cancellations`;
TRUNCATE TABLE `ticket_passengers`;
TRUNCATE TABLE `pnr_bookings`;
TRUNCATE TABLE `schedules`;
TRUNCATE TABLE `passengers`;
TRUNCATE TABLE `berths`;
TRUNCATE TABLE `coaches`;
TRUNCATE TABLE `train_routes`;
TRUNCATE TABLE `trains`;
TRUNCATE TABLE `stations`;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- 1. STATIONS SEED DATA (8 Major Railway Hubs)
-- ============================================================================
INSERT INTO `stations` (`station_id`, `station_code`, `station_name`, `city`, `zone`) VALUES
(1, 'NDLS', 'New Delhi Central Railway Station', 'New Delhi', 'Northern Railway'),
(2, 'MMCT', 'Mumbai Central Terminus', 'Mumbai', 'Western Railway'),
(3, 'HWH',  'Howrah Junction Terminus', 'Kolkata', 'Eastern Railway'),
(4, 'MAS',  'Chennai Central Puratchi Thalaivar', 'Chennai', 'Southern Railway'),
(5, 'SBC',  'KSR Bengaluru City Junction', 'Bengaluru', 'South Western Railway'),
(6, 'ADI',  'Ahmedabad Junction Sabarmati', 'Ahmedabad', 'Western Railway'),
(7, 'CNB',  'Kanpur Central Interchange', 'Kanpur', 'North Central Railway'),
(8, 'PNBE', 'Patna Junction Railway Station', 'Patna', 'East Central Railway');

-- ============================================================================
-- 2. TRAINS SEED DATA (4 High-Profile Passenger Trains)
-- ============================================================================
INSERT INTO `trains` (`train_id`, `train_number`, `train_name`, `train_type`, `source_station_id`, `destination_station_id`) VALUES
(1, '12952', 'Mumbai Tejas Rajdhani Express', 'Superfast', 1, 2), -- NDLS to MMCT
(2, '12301', 'Howrah Rajdhani Special', 'Superfast', 3, 1),       -- HWH to NDLS
(3, '20901', 'Vande Bharat Express Bullet', 'Bullet', 6, 2),        -- ADI to MMCT
(4, '12608', 'Lalbagh Intercity Express', 'Express', 5, 4);        -- SBC to MAS

-- ============================================================================
-- 3. TRAIN ROUTES SEED DATA (12 Network Route Stops & Sequences)
-- ============================================================================
INSERT INTO `train_routes` (`route_id`, `train_id`, `station_id`, `stop_sequence`, `arrival_time`, `departure_time`, `distance_km`) VALUES
-- Train 1: Mumbai Rajdhani (NDLS -> CNB -> ADI -> MMCT)
(1, 1, 1, 1, NULL, '16:55:00', 0),
(2, 1, 7, 2, '21:30:00', '21:35:00', 440),
(3, 1, 6, 3, '04:15:00', '04:25:00', 980),
(4, 1, 2, 4, '08:35:00', NULL, 1384),

-- Train 2: Howrah Rajdhani (HWH -> PNBE -> CNB -> NDLS)
(5, 2, 3, 1, NULL, '16:50:00', 0),
(6, 2, 8, 2, '22:10:00', '22:20:00', 535),
(7, 2, 7, 3, '04:40:00', '04:45:00', 1018),
(8, 2, 1, 4, '10:05:00', NULL, 1447),

-- Train 3: Vande Bharat Bullet (ADI -> MMCT)
(9, 3, 6, 1, NULL, '06:10:00', 0),
(10, 3, 2, 2, '11:35:00', NULL, 492),

-- Train 4: Lalbagh Express (SBC -> MAS)
(11, 4, 5, 1, NULL, '06:20:00', 0),
(12, 4, 4, 2, '12:15:00', NULL, 362);

-- ============================================================================
-- 4. COACHES SEED DATA (12 Coaches across classes)
-- ============================================================================
INSERT INTO `coaches` (`coach_id`, `train_id`, `coach_code`, `coach_class`, `total_seats`) VALUES
-- Train 1 Coaches
(1, 1, 'H1', 'AC1', 4),
(2, 1, 'A1', 'AC2', 4),
(3, 1, 'B1', 'AC3', 4),
(4, 1, 'S1', 'Sleeper', 4),

-- Train 2 Coaches
(5, 2, 'H1', 'AC1', 4),
(6, 2, 'A1', 'AC2', 4),
(7, 2, 'B1', 'AC3', 4),
(8, 2, 'S1', 'Sleeper', 4),

-- Train 3 Coaches (Executive & Chair Car)
(9, 3, 'EC1', 'AC1', 4),
(10, 3, 'CC1', 'AC2', 4),

-- Train 4 Coaches
(11, 4, 'C1', 'AC3', 4),
(12, 4, 'D1', 'Economy', 4);

-- ============================================================================
-- 5. BERTHS SEED DATA (48 Atomic Berths across coaches)
-- ============================================================================
INSERT INTO `berths` (`berth_id`, `coach_id`, `seat_number`, `berth_type`, `quota_type`) VALUES
-- Coach 1 (Train 1 - AC1)
(1, 1, 1, 'Lower', 'General'),
(2, 1, 2, 'Upper', 'General'),
(3, 1, 3, 'Lower', 'Ladies'),
(4, 1, 4, 'Upper', 'Senior_Citizen'),

-- Coach 2 (Train 1 - AC2)
(5, 2, 1, 'Lower', 'General'),
(6, 2, 2, 'Upper', 'General'),
(7, 2, 3, 'Side_Lower', 'Tatkal'),
(8, 2, 4, 'Side_Upper', 'General'),

-- Coach 3 (Train 1 - AC3)
(9, 3, 1, 'Lower', 'General'),
(10, 3, 2, 'Middle', 'General'),
(11, 3, 3, 'Upper', 'General'),
(12, 3, 4, 'Side_Lower', 'Senior_Citizen'),

-- Coach 4 (Train 1 - Sleeper)
(13, 4, 1, 'Lower', 'General'),
(14, 4, 2, 'Middle', 'General'),
(15, 4, 3, 'Upper', 'General'),
(16, 4, 4, 'Side_Lower', 'Ladies'),

-- Coach 5 (Train 2 - AC1)
(17, 5, 1, 'Lower', 'General'),
(18, 5, 2, 'Upper', 'General'),
(19, 5, 3, 'Lower', 'Ladies'),
(20, 5, 4, 'Upper', 'Senior_Citizen'),

-- Coach 6 (Train 2 - AC2)
(21, 6, 1, 'Lower', 'General'),
(22, 6, 2, 'Upper', 'General'),
(23, 6, 3, 'Side_Lower', 'Tatkal'),
(24, 6, 4, 'Side_Upper', 'General'),

-- Coach 7 (Train 2 - AC3)
(25, 7, 1, 'Lower', 'General'),
(26, 7, 2, 'Middle', 'General'),
(27, 7, 3, 'Upper', 'General'),
(28, 7, 4, 'Side_Lower', 'Senior_Citizen'),

-- Coach 8 (Train 2 - Sleeper)
(29, 8, 1, 'Lower', 'General'),
(30, 8, 2, 'Middle', 'General'),
(31, 8, 3, 'Upper', 'General'),
(32, 8, 4, 'Side_Lower', 'Ladies'),

-- Coach 9 (Train 3 - Executive)
(33, 9, 1, 'Lower', 'General'),
(34, 9, 2, 'Upper', 'General'),
(35, 9, 3, 'Lower', 'Tatkal'),
(36, 9, 4, 'Upper', 'Senior_Citizen'),

-- Coach 10 (Train 3 - Chair Car)
(37, 10, 1, 'Lower', 'General'),
(38, 10, 2, 'Upper', 'General'),
(39, 10, 3, 'Side_Lower', 'Ladies'),
(40, 10, 4, 'Side_Upper', 'General'),

-- Coach 11 (Train 4 - AC3)
(41, 11, 1, 'Lower', 'General'),
(42, 11, 2, 'Middle', 'General'),
(43, 11, 3, 'Upper', 'General'),
(44, 11, 4, 'Side_Lower', 'General'),

-- Coach 12 (Train 4 - Economy)
(45, 12, 1, 'Lower', 'General'),
(46, 12, 2, 'Upper', 'General'),
(47, 12, 3, 'Side_Lower', 'Senior_Citizen'),
(48, 12, 4, 'Side_Upper', 'General');

-- ============================================================================
-- 6. PASSENGERS SEED DATA (15 Unique Verified Rail Travelers)
-- ============================================================================
INSERT INTO `passengers` (`passenger_id`, `full_name`, `gender`, `age`, `national_id`, `phone`, `email`) VALUES
(1,  'Dr. AARAV SHARMA',     'M', 45, 'NAT-ID-1001-A', '+919811012345', 'aarav.sharma@research.edu'),
(2,  'PRIYA NAIR',           'F', 29, 'NAT-ID-1002-B', '+919822012346', 'priya.nair@techfirm.com'),
(3,  'VIKRAMADITYA RAO',     'M', 67, 'NAT-ID-1003-C', '+919833012347', 'v.rao@seniorcouncil.in'),
(4,  'ANANYA DESHMUKH',      'F', 24, 'NAT-ID-1004-D', '+919844012348', 'ananya.d@university.edu'),
(5,  'COLONEL RAJESH KHAN',  'M', 58, 'NAT-ID-1005-E', '+919855012349', 'col.rajesh@defservices.in'),
(6,  'MEERA IYER',           'F', 34, 'NAT-ID-1006-F', '+919866012350', 'meera.iyer@analytics.io'),
(7,  'KABIR BANERJEE',       'M', 31, 'NAT-ID-1007-G', '+919877012351', 'kabir.b@capitalmarkets.org'),
(8,  'SNEHA PATEL',          'F', 52, 'NAT-ID-1008-H', '+919888012352', 'sneha.patel@gujarathealth.gov'),
(9,  'ROHAN VERMA',          'M', 22, 'NAT-ID-1009-I', '+919899012353', 'rohan.v@studentnet.edu'),
(10, 'DIVYA CHOUDHARY',      'F', 38, 'NAT-ID-1010-J', '+919810012354', 'divya.c@logisticsglobal.com'),
(11, 'ARJUN SENGUPTA',       'M', 41, 'NAT-ID-1011-K', '+919821012355', 'arjun.s@kolkataworks.in'),
(12, 'ZOYAKHTAR SHEIKH',     'F', 27, 'NAT-ID-1012-L', '+919832012356', 'zoya.sheikh@medcare.org'),
(13, 'PROF. DEEPAK JOSHI',   'M', 71, 'NAT-ID-1013-M', '+919843012357', 'd.joshi@iitfaculty.ac.in'),
(14, 'POOJA BALAKRISHNAN',   'F', 33, 'NAT-ID-1014-N', '+919854012358', 'pooja.b@bengalurucloud.co'),
(15, 'HARSHVARDHAN TIWARI',  'M', 19, 'NAT-ID-1015-O', '+919865012359', 'harsh.tiwari@polytechnic.edu');

-- ============================================================================
-- 7. SCHEDULES SEED DATA (4 Active Operational Runs)
-- ============================================================================
INSERT INTO `schedules` (`schedule_id`, `train_id`, `journey_date`, `departure_time`, `status`) VALUES
(1, 1, '2026-10-15', '2026-10-15 16:55:00', 'Scheduled'), -- Mumbai Rajdhani (NDLS->MMCT)
(2, 2, '2026-10-16', '2026-10-16 16:50:00', 'Scheduled'), -- Howrah Rajdhani (HWH->NDLS)
(3, 3, '2026-10-17', '2026-10-17 06:10:00', 'Scheduled'), -- Vande Bharat (ADI->MMCT)
(4, 4, '2026-10-18', '2026-10-18 06:20:00', 'Scheduled'); -- Lalbagh Express (SBC->MAS)

-- ============================================================================
-- 8. PNR BOOKINGS SEED DATA (15 Distinct PNR Envelopes)
-- ============================================================================
INSERT INTO `pnr_bookings` (`pnr_id`, `pnr_number`, `schedule_id`, `booked_by_passenger_id`, `origin_station_id`, `dest_station_id`, `total_fare`, `booking_status`, `booked_at`) VALUES
-- Schedule 1 Bookings (NDLS to MMCT)
(1,  '2847193850', 1, 1,  1, 2, 4844.00, 'Confirmed', '2026-09-01 10:14:00'),
(2,  '6492048172', 1, 2,  1, 2, 4844.00, 'Confirmed', '2026-09-01 11:20:00'),
(3,  '8174920184', 1, 3,  1, 2, 4844.00, 'Confirmed', '2026-09-02 09:30:00'),
(4,  '1948205739', 1, 4,  1, 2, 4844.00, 'Confirmed', '2026-09-02 14:15:00'),
(5,  '5039281746', 1, 5,  1, 2, 3321.60, 'Confirmed', '2026-09-03 08:45:00'),
(6,  '9284710385', 1, 6,  1, 2, 3321.60, 'Confirmed', '2026-09-03 16:10:00'),
(7,  '3748291048', 1, 7,  1, 2, 2352.80, 'Confirmed', '2026-09-04 12:00:00'),
(8,  '7184920481', 1, 8,  1, 2, 1384.00, 'Confirmed', '2026-09-05 10:00:00'),
(9,  '4829103759', 1, 9,  1, 2, 1384.00, 'Cancelled', '2026-09-06 15:30:00'), -- Will be cancelled
(10, '8294017382', 1, 10, 1, 2, 4844.00, 'Waitlisted', '2026-09-07 11:00:00'), -- WL #1
(11, '3958201948', 1, 11, 1, 2, 4844.00, 'Waitlisted', '2026-09-08 17:25:00'), -- WL #2

-- Schedule 2 Bookings (HWH to NDLS)
(12, '9184729104', 2, 12, 3, 1, 5064.50, 'Confirmed', '2026-09-09 10:15:00'),
(13, '6294018274', 2, 13, 3, 1, 5064.50, 'Confirmed', '2026-09-10 14:40:00'),

-- Schedule 3 Bookings (ADI to MMCT - Vande Bharat)
(14, '5192840182', 3, 14, 6, 2, 2583.00, 'Confirmed', '2026-09-11 09:00:00'),

-- Schedule 4 Bookings (SBC to MAS - Lalbagh)
(15, '7395018274', 4, 15, 5, 4, 452.50,  'Confirmed', '2026-09-12 16:20:00');

-- ============================================================================
-- 9. TICKET PASSENGERS SEED DATA (Passenger Manifest & Seating States)
-- ============================================================================
INSERT INTO `ticket_passengers` (`ticket_item_id`, `pnr_id`, `passenger_id`, `berth_id`, `seat_status`, `waitlist_number`, `fare`) VALUES
-- Schedule 1 Confirmed Seats on Train 1
(1,  1,  1,  1,  'CNF', NULL, 4844.00), -- Coach H1, Seat 1 (Lower)
(2,  2,  2,  2,  'CNF', NULL, 4844.00), -- Coach H1, Seat 2 (Upper)
(3,  3,  3,  3,  'CNF', NULL, 4844.00), -- Coach H1, Seat 3 (Lower)
(4,  4,  4,  4,  'CNF', NULL, 4844.00), -- Coach H1, Seat 4 (Upper)
(5,  5,  5,  5,  'CNF', NULL, 3321.60), -- Coach A1, Seat 1 (Lower)
(6,  6,  6,  6,  'CNF', NULL, 3321.60), -- Coach A1, Seat 2 (Upper)
(7,  7,  7,  9,  'CNF', NULL, 2352.80), -- Coach B1, Seat 1 (Lower)
(8,  8,  8,  13, 'CNF', NULL, 1384.00), -- Coach S1, Seat 1 (Lower)

-- Schedule 1 Cancelled Ticket
(9,  9,  9,  NULL, 'CAN', NULL, 1384.00), -- Cancelled Seat (formerly Coach S1, Seat 2)

-- Schedule 1 Waitlisted Queue
(10, 10, 10, NULL, 'WL', 1, 4844.00), -- Waitlist Position 1
(11, 11, 11, NULL, 'WL', 2, 4844.00), -- Waitlist Position 2

-- Schedule 2 Confirmed Seats on Train 2
(12, 12, 12, 17, 'CNF', NULL, 5064.50), -- Coach H1, Seat 1 (Lower)
(13, 13, 13, 18, 'CNF', NULL, 5064.50), -- Coach H1, Seat 2 (Upper)

-- Schedule 3 Confirmed Seat on Train 3
(14, 14, 14, 33, 'CNF', NULL, 2583.00), -- Coach EC1, Seat 1 (Lower)

-- Schedule 4 Confirmed Seat on Train 4
(15, 15, 15, 41, 'CNF', NULL, 452.50);  -- Coach C1, Seat 1 (Lower)

-- ============================================================================
-- 10. CANCELLATIONS SEED DATA (Recorded Refunds & Charges)
-- ============================================================================
INSERT INTO `cancellations` (`cancellation_id`, `ticket_item_id`, `pnr_id`, `refund_amount`, `cancellation_charge`, `cancelled_at`) VALUES
(1, 9, 9, 1245.60, 138.40, '2026-09-08 18:40:00');

-- ============================================================================
-- 11. PNR AUDIT LOGS SEED DATA (Immutable Historical Audit Trail)
-- ============================================================================
INSERT INTO `pnr_audit_logs` (`log_id`, `pnr_id`, `ticket_item_id`, `old_seat_status`, `new_seat_status`, `berth_assigned`, `reason`, `logged_at`) VALUES
(1,  1,  1,  'NEW', 'CNF', 1,    'Initial booking: Confirmed berth allocated', '2026-09-01 10:14:00'),
(2,  2,  2,  'NEW', 'CNF', 2,    'Initial booking: Confirmed berth allocated', '2026-09-01 11:20:00'),
(3,  3,  3,  'NEW', 'CNF', 3,    'Initial booking: Confirmed berth allocated', '2026-09-02 09:30:00'),
(4,  4,  4,  'NEW', 'CNF', 4,    'Initial booking: Confirmed berth allocated', '2026-09-02 14:15:00'),
(5,  5,  5,  'NEW', 'CNF', 5,    'Initial booking: Confirmed berth allocated', '2026-09-03 08:45:00'),
(6,  6,  6,  'NEW', 'CNF', 6,    'Initial booking: Confirmed berth allocated', '2026-09-03 16:10:00'),
(7,  7,  7,  'NEW', 'CNF', 9,    'Initial booking: Confirmed berth allocated', '2026-09-04 12:00:00'),
(8,  8,  8,  'NEW', 'CNF', 13,   'Initial booking: Confirmed berth allocated', '2026-09-05 10:00:00'),
(9,  9,  9,  'NEW', 'CNF', 14,   'Initial booking: Confirmed berth allocated', '2026-09-06 15:30:00'),
(10, 9,  9,  'CNF', 'CAN', NULL, 'Passenger cancelled booking prior to charting', '2026-09-08 18:40:00'),
(11, 10, 10, 'NEW', 'WL',  NULL, 'Initial booking: Placed in waitlist queue position #1', '2026-09-07 11:00:00'),
(12, 11, 11, 'NEW', 'WL',  NULL, 'Initial booking: Placed in waitlist queue position #2', '2026-09-08 17:25:00'),
(13, 12, 12, 'NEW', 'CNF', 17,   'Initial booking: Confirmed berth allocated', '2026-09-09 10:15:00'),
(14, 13, 13, 'NEW', 'CNF', 18,   'Initial booking: Confirmed berth allocated', '2026-09-10 14:40:00'),
(15, 14, 14, 'NEW', 'CNF', 33,   'Initial booking: Confirmed berth allocated', '2026-09-11 09:00:00'),
(16, 15, 15, 'NEW', 'CNF', 41,   'Initial booking: Confirmed berth allocated', '2026-09-12 16:20:00');
