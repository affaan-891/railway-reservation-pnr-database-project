# Comprehensive DBMS Viva Voce Defense & Technical Interview Guide

**Domain**: High-Throughput Railway Seat Reservation & Dynamic PNR Waitlist Engine  
**Course Code**: CS-DBMS / SE-304 Advanced Database Management Systems  
**Evaluation Standard**: University Oral Examination, Lab Defense & Systems Architecture Review

---

### Question 1: How does the system guarantee zero double-booking during concurrent ticket reservations under peak traffic (e.g., Tatkal rush)?
**Answer:**
Zero double-booking is enforced at two distinct defensive tiers:
1. **Pessimistic Concurrency Locking at the Procedure Tier (`SELECT ... FOR UPDATE`)**:
   In `sp_book_railway_ticket`, when a transaction searches for an unassigned berth in a requested coach class, it executes:
   ```sql
   SELECT b.berth_id INTO v_allocated_berth_id
   FROM berths b
   WHERE ...
   LIMIT 1
   FOR UPDATE;
   ```
   Under InnoDB, `SELECT ... FOR UPDATE` acquires an exclusive row-level X-lock on the matching berth row. Any concurrent transaction attempting to read or claim the exact same berth is placed in a lock-wait queue until the first transaction executes `COMMIT` or `ROLLBACK`.
2. **Defensive Trigger Invariant (`trg_prevent_berth_double_booking`)**:
   Even if an external client executes an unhedged ad-hoc `INSERT` or `UPDATE` outside the procedure, the `BEFORE INSERT` and `BEFORE UPDATE` triggers on `ticket_passengers` scan active confirmed tickets (`seat_status = 'CNF'`) for the same `schedule_id`. If a collision is detected, the trigger fires `SIGNAL SQLSTATE '45000'`, instantly terminating the offending transaction.

---

### Question 2: Why did you choose Pessimistic Locking over Optimistic Concurrency Control (OCC) with a Version Column for berth allocation?
**Answer:**
- **High Contention vs Low Contention Dynamics**: Optimistic Concurrency Control (OCC) assumes conflicts are rare. In OCC, each transaction reads without locking and validates a `version_number` at commit time. If a version mismatch occurs, the transaction rolls back and retries.
- **The "Thundering Herd" Problem in Seat Allocation**: During high-demand railway bookings (like festival rushes or opening of booking windows), hundreds of users compete for the exact same few lower berths within milliseconds. Under OCC, 99 out of 100 concurrent requests would abort due to conflict, causing catastrophic retry storms, high CPU thrashing, and elevated latency.
- **Pessimistic Locking Guarantees Deterministic Queuing**: By utilizing InnoDB's row-level exclusive locks with `FOR UPDATE`, requests are serialized in the database engine's native lock wait queue. The first transaction acquires the lock, claims the seat, and commits; subsequent transactions seamlessly slide to the next available berth without failing the passenger.

---

### Question 3: What is the MySQL Trigger Mutating Table Restriction (Error 1442), and how does your architecture resolve it?
**Answer:**
- **The Constraint**: In MySQL 8.0, an `AFTER UPDATE` trigger defined on table $T$ is prohibited from executing an explicit `UPDATE` or `DELETE` statement on table $T$. Violating this raises:
  `ERROR 1442 (HY000): Can't update table 'ticket_passengers' in stored function/trigger because it is already being used by statement which invoked this stored function/trigger.`
  This safety check prevents infinite trigger recursion and non-deterministic row states.
- **Architectural Solution in this Project**:
  Instead of placing the waitlist promotion trigger directly on `ticket_passengers` upon update, the event is decoupled and attached to the `cancellations` financial adjustment ledger:
  ```sql
  CREATE TRIGGER trg_auto_promote_waitlist_on_cancellation
  AFTER INSERT ON cancellations
  FOR EACH ROW ...
  ```
  When a ticket is cancelled, an insertion occurs in `cancellations`. Because the triggering table is `cancellations`, MySQL permits the trigger to safely update target table `ticket_passengers` (promoting the waitlisted passenger to `CNF` and adjusting subsequent queue ranks) without encountering Error 1442.

---

### Question 4: Explain the Two-Phase Locking (2PL) protocol. How does InnoDB ensure Serializability, and how are deadlocks mitigated?
**Answer:**
- **Two-Phase Locking (2PL)** guarantees serializability across transactions through two phases:
  1. **Growing Phase**: The transaction may acquire locks (shared or exclusive) but cannot release any lock.
  2. **Shrinking Phase**: Once the transaction releases its first lock, it enters the shrinking phase and can acquire no further locks.
- In InnoDB, strict Two-Phase Locking is implemented: all row locks acquired during transaction execution are held until the explicit transaction boundary (`COMMIT` or `ROLLBACK`).
- **Deadlock Mitigation**:
  - **Deterministic Lock Acquisition Ordering**: In our queries and stored procedures, rows are consistently queried using deterministic sorting (`ORDER BY b.berth_id ASC`).
  - **InnoDB Deadlock Detection**: InnoDB maintains a Wait-For Graph (WFG) in memory. When a cycle is detected, InnoDB automatically elects the transaction with the smallest undo log footprint as the victim, issues a rollback, and returns error code `1213 (Deadlock found when trying to get lock; try restarting transaction)`.

---

### Question 5: How does the Dynamic Waitlist FIFO Promotion algorithm work upon cancellation? What is its computational complexity?
**Answer:**
When a confirmed ticket holding a physical berth is cancelled:
1. **Identification of Vacated Resource**: The trigger extracts `schedule_id` and `v_vacated_berth_id`.
2. **Top Waitlist Candidate Lookup**:
   ```sql
   SELECT ticket_item_id, pnr_id, waitlist_number
   INTO v_next_ticket_id, v_next_pnr_id, v_next_old_wl
   FROM ticket_passengers tp
   JOIN pnr_bookings pb ON tp.pnr_id = pb.pnr_id
   WHERE pb.schedule_id = v_schedule_id AND tp.seat_status = 'WL'
   ORDER BY tp.waitlist_number ASC LIMIT 1;
   ```
   Thanks to the composite index `(seat_status, waitlist_number)`, this is an $\mathcal{O}(\log N)$ B+ tree index scan.
3. **Berth Reassignment**: The passenger's status is atomically upgraded to `'CNF'`, `berth_id` is set to `v_vacated_berth_id`, and `waitlist_number` is set to `NULL`.
4. **Queue Re-Sequencing**: All subsequent waitlisted passengers on that schedule have their queue numbers decremented by 1:
   ```sql
   UPDATE ticket_passengers tp
   JOIN pnr_bookings pb ON tp.pnr_id = pb.pnr_id
   SET tp.waitlist_number = tp.waitlist_number - 1
   WHERE pb.schedule_id = v_schedule_id AND tp.seat_status = 'WL'
     AND tp.waitlist_number > v_next_old_wl;
   ```
5. **Audit Logging**: Every transition is immutably recorded in `pnr_audit_logs`.

---

### Question 6: Walk through the 3NF normalization justification of the database schema. Why is `pnr_bookings` separate from `ticket_passengers`?
**Answer:**
- **1NF**: Every column contains atomic values. Multi-passenger bookings cannot be stored as arrays or comma-delimited strings in a single booking record.
- **2NF**: In a railway reservation system, a single transaction (PNR) can book travel for up to 6 passengers. If all data were in one table:
  - `(pnr_number, passenger_id)` would form a composite primary key.
  - Attributes like `total_fare`, `schedule_id`, `origin_station_id`, and `booked_at` depend only on `pnr_number`, resulting in a Partial Functional Dependency (violating 2NF).
  - Decomposing into `pnr_bookings` (header) and `ticket_passengers` (line item) eliminates this partial dependency.
- **3NF**: In `ticket_passengers`, storing passenger details (`passenger_name`, `age`, `gender`) would create a transitive dependency:
  `ticket_item_id -> passenger_id -> passenger_name`
  If a passenger changes their phone number or name, updating it across dozens of historical tickets would risk update anomalies. Isolating demographic data into `passengers` achieves complete 3NF compliance.

---

### Question 7: Explain the composite index `idx_ticket_status_wl (seat_status, waitlist_number)` and how the B+ Tree handles range scans.
**Answer:**
- **Leftmost Prefix Rule in B+ Trees**:
  The index `(seat_status, waitlist_number)` creates composite keys sorted primarily by `seat_status`, and secondarily by `waitlist_number`.
- **Query Optimization**:
  When evaluating:
  ```sql
  WHERE seat_status = 'WL' ORDER BY waitlist_number ASC LIMIT 1;
  ```
  The MySQL query optimizer locates the first `'WL'` leaf page in $\mathcal{O}(\log K)$ operations and instantly reads the top row (`waitlist_number = 1`) without scanning confirmed (`CNF`) or cancelled (`CAN`) rows, completely avoiding an expensive file-sort (`Using filesort`).
- **Index Condition Pushdown (ICP)**:
  MySQL pushes the `waitlist_number` filter directly to the storage engine layer, minimizing disk I/O and buffer pool lookups.

---

### Question 8: Why are foreign key actions configured with `ON DELETE RESTRICT` for master tables and `ON DELETE CASCADE` for line items?
**Answer:**
- **Data Integrity via `ON DELETE RESTRICT`**:
  On master entities (`stations`, `trains`, `schedules`, `passengers`), accidental deletion of a station or train should never orphan ongoing or historical passenger reservations. `RESTRICT` halts any `DELETE` operation if referenced by dependent records, ensuring strict referential integrity and audit compliance.
- **Lifecycle Coupling via `ON DELETE CASCADE`**:
  Weak or child entities that have an existential dependence on their parent (such as `coaches -> berths`, `pnr_bookings -> ticket_passengers`, and `ticket_passengers -> cancellations`) are configured with `CASCADE`. If a draft or invalid test booking is purged, its child ticket line items are systematically cleaned up, preventing orphan row accumulation.

---

### Question 9: What ACID guarantees are maintained by `sp_book_railway_ticket`, and what happens if a database crash occurs midway?
**Answer:**
- **Atomicity**: The procedure encapsulates all operations within `START TRANSACTION` and `COMMIT`. An exit handler catches any `SQLEXCEPTION`:
  ```sql
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
      ROLLBACK;
      RESIGNAL;
  END;
  ```
  If a hardware failure or constraint collision occurs after generating the PNR but before writing `ticket_passengers`, the entire transaction is rolled back via the InnoDB Undo Log.
- **Consistency**: All `CHECK` constraints (e.g. `age > 0`, `fare >= 0`, `origin <> dest`) and trigger validation invariants are verified before write serialization.
- **Isolation**: Handled under `REPEATABLE READ` (default) with explicit `FOR UPDATE` pessimistic row locks, preventing phantom reads and dirty reads.
- **Durability**: Upon `COMMIT`, InnoDB flushes transaction log buffers to the Redo Log (`ib_logfile`) on disk, ensuring recovery even during sudden power outages.

---

### Question 10: How does `fn_calculate_train_occupancy_ratio` handle division by zero, and why is it declared `READS SQL DATA DETERMINISTIC`?
**Answer:**
- **Division by Zero Protection**:
  If a train has no registered coaches, `SUM(total_seats)` returns 0 or `NULL`. In the function:
  ```sql
  IF v_total_capacity > 0 THEN
      SET v_occupancy_ratio = ROUND((v_booked_seats / v_total_capacity) * 100.0, 2);
  ELSE
      SET v_occupancy_ratio = 0.00;
  END IF;
  ```
  This cleanly prevents `NULL` results and runtime mathematical exceptions.
- **Routine Characteristics (`READS SQL DATA DETERMINISTIC`)**:
  - `READS SQL DATA`: Informs the MySQL query planner and binary log replication engine that the routine executes `SELECT` statements without modifying table state.
  - `DETERMINISTIC`: Declares that given identical underlying table rows for a given `p_schedule_id`, the function returns identical output, enabling query plan caching and binary logging safety when `binlog_format = STATEMENT` or `MIXED`.
