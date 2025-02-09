-- Test Case 1: Queue to Reserved
BEGIN;
UPDATE reservations SET status = 'reserved'
WHERE id = '[FIRST_QUEUE_ID]';

-- Test Case 2: Position Reordering
SELECT id, status, position_in_queue FROM reservations
WHERE release_id = 1 ORDER BY position_in_queue;