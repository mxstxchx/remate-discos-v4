-- Test Scenario 1: Queue to Reserved
BEGIN;
-- Setup initial queue
INSERT INTO reservations (release_id, session_id, status)
VALUES 
  (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue'),
  (1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');

-- Change first item to reserved
UPDATE reservations 
SET status = 'reserved'
WHERE id = (SELECT id FROM reservations WHERE status = 'in_queue' ORDER BY position_in_queue LIMIT 1);

-- Verify position reordering
SELECT id, status, position_in_queue 
FROM reservations 
WHERE release_id = 1 
ORDER BY COALESCE(position_in_queue, 0);
COMMIT;