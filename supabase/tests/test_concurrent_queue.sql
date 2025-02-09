-- Test Case 1: Empty Queue Entry
BEGIN;
INSERT INTO reservations (release_id, session_id, status)
VALUES (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');

-- Test Case 2: Existing Queue Entry
-- Run in separate transaction
BEGIN;
INSERT INTO reservations (release_id, session_id, status)
VALUES (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');

-- Verification queries
SELECT id, status, position_in_queue FROM reservations WHERE release_id = 1 ORDER BY position_in_queue;