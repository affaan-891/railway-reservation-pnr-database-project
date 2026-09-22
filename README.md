# 🚆 Railway Seat Reservation & Dynamic Waitlist (PNR) Engine

[![MySQL 8.0+](https://img.shields.io/badge/MySQL-8.0%2B-blue.svg?logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Database Architecture](https://img.shields.io/badge/Architecture-3NF%20Certified-success.svg)](#database-architecture)
[![ACID Compliant](https://img.shields.io/badge/Transactions-ACID%20Pessimistic%20Locking-orange.svg)](#concurrency--transaction-management)
[![Triggers & Procedures](https://img.shields.io/badge/Automations-Triggers%20%26%20Stored%20Procs-purple.svg)](#triggers--stored-procedures)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An industrial-grade, academic benchmark relational database repository modeling a high-concurrency **Railway Seat Reservation & Dynamic Passenger Name Record (PNR) Engine**. Specifically architected for university computer science and software engineering students preparing for semester DBMS projects, practical lab submissions, and technical viva voce defenses.

---

## 📑 Table of Contents
1. [System Overview & Architecture](#-system-overview--architecture)
2. [Key Database Features](#-key-database-features)
3. [Database Schema & 3NF Normalization](#-database-schema--3nf-normalization)
4. [Concurrency & Transaction Management](#-concurrency--transaction-management)
5. [Triggers & Stored Procedures](#-triggers--stored-procedures)
6. [Repository Structure](#-repository-structure)
7. [Installation & Setup Guide](#-installation--setup-guide)
8. [Analytical Views & Viva Queries Preview](#-analytical-views--viva-queries-preview)
9. [Viva Voce & Technical Defense Prep](#-viva-voce--technical-defense-prep)
10. [Git Setup & Deployment Commands](#-git-setup--deployment-commands)

---

## 🚄 System Overview & Architecture

Passenger rail transit reservation systems are among the most demanding transactional OLTP workloads in computing. They require:
- Absolute **zero double-booking** under flash-sale traffic surges (e.g., Tatkal quota windows).
- **Pessimistic row-level locking** (`SELECT ... FOR UPDATE`) to prevent race conditions across concurrent booking threads.
- Dynamic **First-In, First-Out (FIFO) Waitlist queues** that automatically promote waitlisted passengers (`WL` ➔ `CNF`) upon ticket cancellations.
- Immutable **audit trail ledgers** capturing every state transition and berth reallocation.

```
       [ Client / Passenger Request ]
                     │
                     ▼
       ┌───────────────────────────────┐
       │   sp_book_railway_ticket()    │
       │   (Explicit ACID Transaction) │
       └──────────────┬────────────────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
[ Vacant Berth Found? ]       [ Capacity 100% Full? ]
        │                                   │
        ├─► YES: Lock Row (FOR UPDATE)      └─► YES: Calculate MAX(WL) + 1
        │        Confirm Berth ('CNF')               Queue Status ('WL')
        │        Generate 10-Digit PNR               Generate 10-Digit PNR
        │                                            No Berth Linked
        ▼
[ trg_prevent_berth_double_booking ]
        │
        └─► Guaranteed Zero Collision Invariant ──► COMMIT
```

---

## 🌟 Key Database Features

- **Strict 3NF Compliance**: Completely free of partial and transitive dependencies across 11 normalized tables.
- **Pessimistic Row-Level Concurrency Control**: Avoids retry thrashing during high-volume seat allocations.
- **Automated Waitlist Cascade Engine**: Decoupled cancellation trigger that reallocates vacated berths and shifts queue ranks without encountering MySQL Error 1442.
- **Tiered Cancellation Penalty Rules**: Computes dynamic administrative deductions (10%, 25%, 50%) based on journey departure proximity.
- **Analytical Reporting Views**: Ready-to-use reservation chart manifests and route-level financial performance summaries.
- **Comprehensive Academic Viva Kit**: 10 deep-dive questions and answers addressing state-machine synchronization, 2PL, and indexing theory.

---

## 🗄️ Database Schema & 3NF Normalization

The database `railway_pnr_db` comprises **11 normalized tables**:

| Table Name | Primary Key | Description & Cardinality |
| :--- | :--- | :--- |
| `stations` | `station_id` | Geographic terminal nodes with unique alphanumeric station codes (`NDLS`, `MMCT`). |
| `trains` | `train_id` | Master catalog of train services with distinct speed classes (`Superfast`, `Bullet`). |
| `train_routes` | `route_id` | Ordered sequence of intermediate station stops with cumulative distances. |
| `coaches` | `coach_id` | Rolling stock carriages assigned to trains (`AC1`, `AC2`, `AC3`, `Sleeper`, `Economy`). |
| `berths` | `berth_id` | Physical seating units categorized by ergonomics (`Lower`, `Upper`) and quotas. |
| `passengers` | `passenger_id` | Master directory of travelers with unique government IDs and contact records. |
| `schedules` | `schedule_id` | Concrete dated runs linking rolling stock to calendar departure timestamps. |
| `pnr_bookings` | `pnr_id` | Header transactional dossier referenced by a unique 10-digit numeric PNR. |
| `ticket_passengers` | `ticket_item_id` | Individual traveler manifestations holding seat status (`CNF`, `RAC`, `WL`, `CAN`). |
| `cancellations` | `cancellation_id` | Ledger capturing penalty calculations and net refund disbursements. |
| `pnr_audit_logs` | `log_id` | Immutable append-only historical log of all seat status modifications. |

> Detailed data dictionary, column definitions, and Mermaid.js ERD are available in [`docs/ERD.md`](docs/ERD.md).

---

## 🔒 Concurrency & Transaction Management

In high-concurrency systems, race conditions can cause two concurrent booking requests to claim the same physical berth simultaneously. This repository eliminates race conditions using a dual-layer strategy:

### 1. Pessimistic Row Locking (`SELECT ... FOR UPDATE`)
```sql
SELECT b.berth_id INTO v_allocated_berth_id
FROM berths b
JOIN coaches c ON b.coach_id = c.coach_id
WHERE c.train_id = v_train_id
  AND c.coach_class = p_preferred_class
  AND b.berth_id NOT IN (
      SELECT tp.berth_id
      FROM ticket_passengers tp
      JOIN pnr_bookings pb ON tp.pnr_id = pb.pnr_id
      WHERE pb.schedule_id = p_schedule_id
        AND tp.seat_status = 'CNF'
        AND tp.berth_id IS NOT NULL
  )
ORDER BY b.berth_id ASC
LIMIT 1
FOR UPDATE;
```
By issuing `FOR UPDATE`, InnoDB places an exclusive X-lock on the selected berth row, forcing competing transactions into a FIFO wait queue.

### 2. Double-Booking Interceptor Trigger
```sql
CREATE TRIGGER trg_prevent_berth_double_booking_insert
BEFORE INSERT ON ticket_passengers
FOR EACH ROW
...
IF v_collision_count > 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Concurrency Conflict: Berth already booked for this schedule.';
END IF;
```

---

## ⚙️ Triggers & Stored Procedures

### Triggers (`database/02_triggers.sql`)
- `trg_prevent_berth_double_booking_insert`: Aborts duplicate berth allocations on the same train schedule.
- `trg_prevent_berth_double_booking_update`: Validates berth reassignments during status updates.
- `trg_calculate_cancellation_penalty`: Computes dynamic tiered cancellation deductions (10% to 50%) and net refunds.
- `trg_auto_promote_waitlist_on_cancellation`: Promotes the top waitlisted passenger (WL #1) to confirmed status upon cancellation and shifts remaining queue ranks.
- `trg_audit_ticket_status_update`: Appends immutable audit records on status changes.

### Stored Procedures & Functions (`database/03_procedures.sql`)
- `sp_book_railway_ticket(...)`: Atomic ticket booking engine with preferred berth allocation, automatic waitlisting fallback, and 10-digit PNR generation.
- `sp_process_ticket_cancellation(...)`: Atomic cancellation procedure that updates ledger records and triggers automated waitlist promotion.
- `fn_calculate_train_occupancy_ratio(p_schedule_id)`: Deterministic stored function returning booked occupancy percentage.

---

## 📁 Repository Structure

```
railway-reservation-pnr-database-project/
├── database/
│   ├── 01_schema.sql            # Normalized 3NF DDL with table constraints & indexes
│   ├── 02_triggers.sql          # Concurrency safeguards, cancellation penalties & auto-promotion
│   ├── 03_procedures.sql        # ACID booking & cancellation transactions & occupancy function
│   ├── 04_views_and_queries.sql # Reservation charts, route revenue views & 5 viva queries
│   └── 05_seed_data.sql         # 8 stations, 4 trains, 12 routes, 12 coaches, 48 berths & bookings
├── docs/
│   ├── ERD.md                   # Crow's Foot Mermaid.js ERD, data dictionary & 3NF proofs
│   └── VIVA_QUESTIONS.md        # 10 rigorous viva voce questions with theoretical explanations
└── README.md                    # Project documentation, architecture & quickstart guide
```

---

## 🚀 Installation & Setup Guide

### Prerequisites
- MySQL Community Server 8.0 or higher (or XAMPP / WampServer / Docker)
- MySQL CLI Client or MySQL Workbench / DBeaver

### One-Click CLI Import
Open your terminal (PowerShell, Bash, or Command Prompt) and execute scripts sequentially:

```bash
# 1. Login to MySQL and build schema
mysql -u root -p < database/01_schema.sql

# 2. Deploy triggers
mysql -u root -p < database/02_triggers.sql

# 3. Create stored procedures and functions
mysql -u root -p < database/03_procedures.sql

# 4. Create analytical views
mysql -u root -p < database/04_views_and_queries.sql

# 5. Populate seed data
mysql -u root -p < database/05_seed_data.sql
```

### Verification in MySQL
```sql
USE railway_pnr_db;

-- Check operational reservation chart
SELECT * FROM vw_train_pnr_chart LIMIT 10;

-- Check route financial metrics
SELECT * FROM vw_route_revenue_analysis;

-- Test atomic booking procedure
CALL sp_book_railway_ticket(
    1,                  -- p_schedule_id (Mumbai Rajdhani)
    5,                  -- p_booker_id
    15,                 -- p_passenger_id
    1,                  -- p_origin_station (NDLS)
    2,                  -- p_dest_station (MMCT)
    'AC1',              -- p_preferred_class
    'Lower',            -- p_preferred_berth
    @pnr_number,        -- OUT: Generated 10-digit PNR
    @seat_status        -- OUT: CNF or WL
);

SELECT @pnr_number AS Generated_PNR, @seat_status AS Booking_Status;
```

---

## 📊 Analytical Views & Viva Queries Preview

### 1. Train Reservation Chart Manifest (`vw_train_pnr_chart`)
```sql
SELECT train_number, passenger_name, coach_code, seat_number, berth_type, seat_status, waitlist_number
FROM vw_train_pnr_chart
WHERE schedule_id = 1;
```

### 2. High Occupancy Train Schedules (Complex Query Q1)
```sql
SELECT
    s.schedule_id,
    t.train_number,
    t.train_name,
    COUNT(CASE WHEN tp.seat_status = 'CNF' THEN 1 END) AS confirmed_bookings,
    COUNT(CASE WHEN tp.seat_status = 'WL' THEN 1 END) AS waitlist_queue_length,
    ROUND((COUNT(CASE WHEN tp.seat_status = 'CNF' THEN 1 END) / NULLIF(cap.total_capacity, 0)) * 100.0, 2) AS occupancy_percentage
FROM schedules s
JOIN trains t ON s.train_id = t.train_id
LEFT JOIN (SELECT train_id, SUM(total_seats) AS total_capacity FROM coaches GROUP BY train_id) cap ON t.train_id = cap.train_id
LEFT JOIN pnr_bookings pb ON s.schedule_id = pb.schedule_id
LEFT JOIN ticket_passengers tp ON pb.pnr_id = tp.pnr_id
GROUP BY s.schedule_id, t.train_number, t.train_name, s.journey_date, cap.total_capacity
HAVING occupancy_percentage >= 70.00;
```

---

## 🎓 Viva Voce & Technical Defense Prep

Review [`docs/VIVA_QUESTIONS.md`](docs/VIVA_QUESTIONS.md) for complete answers to frequently asked technical questions:
1. Double-booking prevention during peak Tatkal booking windows.
2. Pessimistic Locking vs Optimistic Concurrency Control (OCC).
3. Overcoming MySQL Trigger Error 1442 (Mutating Table Restriction).
4. Two-Phase Locking (2PL) and InnoDB deadlock resolution.
5. Dynamic Waitlist FIFO promotion mechanics and time complexity.
6. 3NF normalization proofs and anomaly elimination.
7. B+ Tree composite index scans on `(seat_status, waitlist_number)`.
8. Foreign key cascades vs restrict policies.
9. ACID guarantees and recovery via Undo/Redo logs.
10. Deterministic routines and division by zero safeguards.

---

## 🛠️ Git Setup & Deployment Commands

To push this repository to your GitHub account:

```powershell
# 1. Initialize git repository
git init

# 2. Link remote GitHub repository
git remote add origin https://github.com/affaan-891/railway-reservation-pnr-database-project.git

# 3. Pull existing remote files (such as LICENSE)
git pull origin main --allow-unrelated-histories

# 4. Stage and commit all database project files
git add .
git commit -m "feat: complete railway reservation and dynamic PNR waitlist engine with 3NF schema, triggers, procedures and ERD"

# 5. Push to main branch
git branch -M main
git push -u origin main
```

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.

**Author**: [Muhammad Affaan](https://github.com/affaan-891)  
**Target Course**: Database Management Systems (CS / SE)
