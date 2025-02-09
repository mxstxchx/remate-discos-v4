# Queue Testing Instructions - Remate Discos V4

## Repository Context
- Name: remate-discos-v4
- Branch: feature/database-schema (current)
- Last commit: 0f7804d9283c0a6dd6e5340b663639f9ec8649bf
- Structure: 
  ```
  /src
    /lib
      /db
        /migrations           # SQL implementations
          00042_queue_maintenance.sql
  /docs                      # Implementation checkpoints
  ```

## Implementation Progress
Sequential checkpoints (most recent first):
1. CHECKPOINT_20250208_2000.md: Current state & test plan
2. CHECKPOINT_20250208_1945.md: Constraint handling
3. CHECKPOINT_20250208_1915.md: Queue maintenance implementation
4. CHECKPOINT_20250208_1555.md: Position management bugs
5. CHECKPOINT_20250208_1552.md: Queue reordering issues
6. CHECKPOINT_20250208_1549.md: Position maintenance start
7. CHECKPOINT_20250208_1544.md: Initial queue constraints

## Development Environment
1. Database Setup
```bash
# Reset database and run migrations
supabase db reset
```

2. Schema State
```sql
-- Current constraint
CONSTRAINT valid_queue_position CHECK (
  (status = 'in_queue' AND position_in_queue IS NOT NULL) OR
  (status != 'in_queue' AND position_in_queue IS NULL)
)

-- Working trigger
CREATE TRIGGER queue_positions
  BEFORE INSERT OR UPDATE ON reservations
  FOR EACH ROW 
  EXECUTE FUNCTION manage_queue_positions();
```

3. Test Data State
```sql
-- Current queue entries
id: 7e4a029e-61ed-4240-a0bb-b8f251d0af2e (position 1)
id: 4a6b43cb-23b1-4b6b-8519-59f2e107334e (position 2)

-- Reset if needed
DELETE FROM reservations WHERE release_id = 1;
INSERT INTO reservations (id, release_id, session_id, status)
VALUES 
('7e4a029e-61ed-4240-a0bb-b8f251d0af2e', 1, 
'123e4567-e89b-12d3-a456-426614174001', 'in_queue'),
('4a6b43cb-23b1-4b6b-8519-59f2e107334e', 1,
'123e4567-e89b-12d3-a456-426614174001', 'in_queue');
```

## Implementation Details
1. Working Patterns
- Single BEFORE trigger for all position management
- Direct position calculation in trigger function
- Transaction-safe position updates
- Automatic gap prevention

2. Avoided Patterns (Known Issues)
- Multiple triggers causing recursion
- AFTER triggers for position updates
- Direct position updates without transaction safety
- Stack depth exceeded errors

## Required Tests
From CHECKPOINT_20250208_2000.md:

1. Concurrent Queue Entry
```sql
BEGIN;
INSERT INTO reservations (id, release_id, session_id, status)
VALUES (gen_random_uuid(), 1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');
-- Run in separate transaction:
INSERT INTO reservations (id, release_id, session_id, status)
VALUES (gen_random_uuid(), 1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');
```

2. Simultaneous Status Changes
```sql
BEGIN;
UPDATE reservations SET status = 'reserved' 
WHERE id = '7e4a029e-61ed-4240-a0bb-b8f251d0af2e';
-- Run in separate transaction:
UPDATE reservations SET status = 'cancelled'
WHERE id = '4a6b43cb-23b1-4b6b-8519-59f2e107334e';
```

3. Mixed Operations
```sql
BEGIN;
INSERT INTO reservations (id, release_id, session_id, status)
VALUES (gen_random_uuid(), 1, '123e4567-e89b-12d3-a456-426614174001', 'in_queue');
UPDATE reservations SET status = 'cancelled'
WHERE id = '7e4a029e-61ed-4240-a0bb-b8f251d0af2e';
```

## Next Steps
1. Run concurrent operation tests as documented
2. Document any edge cases and race conditions found
3. Verify position integrity after each test
4. Consider merge to main if all tests pass