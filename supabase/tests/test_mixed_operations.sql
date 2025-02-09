-- Test Scenario 1: Insert + Status Change
BEGIN;
-- Setup initial state
INSERT INTO reservations (release_id, session_id, status)
VALUES (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');

-- In another transaction
BEGIN;
INSERT INTO reservations (release_id, session_id, status)
VALUES (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');

UPDATE reservations 
SET status = 'cancelled'
WHERE id = (SELECT id FROM reservations WHERE status = 'in_queue' ORDER BY position_in_queue LIMIT 1);

-- Verify queue integrity
SELECT id, status, position_in_queue 
FROM reservations 
WHERE release_id = 1 
ORDER BY COALESCE(position_in_queue, 0);