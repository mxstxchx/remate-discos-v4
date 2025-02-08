-- Status-aware queue position management
CREATE OR REPLACE FUNCTION reorder_queue_positions(p_release_id bigint)
RETURNS void AS $$
DECLARE
  v_max_tries integer := 3;
  v_current_try integer := 0;
  v_success boolean := false;
BEGIN
  WHILE v_current_try < v_max_tries AND NOT v_success LOOP
    BEGIN
      -- Lock all queue entries for atomic update
      WITH ordered_positions AS (
        SELECT 
          id,
          ROW_NUMBER() OVER (
            ORDER BY COALESCE(position_in_queue, 2147483647),
            reserved_at ASC
          ) as new_position
        FROM reservations
        WHERE release_id = p_release_id
          AND status = 'in_queue'
        FOR UPDATE SKIP LOCKED
      )
      UPDATE reservations r
      SET 
        position_in_queue = op.new_position,
        updated_at = NOW()
      FROM ordered_positions op
      WHERE r.id = op.id;

      v_success := true;
      RETURN;
    EXCEPTION WHEN deadlock_detected THEN
      v_current_try := v_current_try + 1;
      IF v_current_try < v_max_tries THEN
        PERFORM pg_sleep(0.1 * v_current_try);
        CONTINUE;
      END IF;
      RAISE;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Queue position maintenance trigger
CREATE OR REPLACE FUNCTION maintain_queue_positions()
RETURNS TRIGGER AS $$
BEGIN
  -- Handle queue entry/exit
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'in_queue' AND NEW.status != 'in_queue' THEN
      -- Exiting queue
      NEW.position_in_queue := NULL;
      PERFORM reorder_queue_positions(NEW.release_id);
    ELSIF OLD.status != 'in_queue' AND NEW.status = 'in_queue' THEN
      -- Entering queue
      SELECT COALESCE(MAX(position_in_queue) + 1, 1)
      INTO NEW.position_in_queue
      FROM reservations
      WHERE release_id = NEW.release_id
        AND status = 'in_queue';
    END IF;
  END IF;

  -- Handle deletion
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'in_queue' THEN
      PERFORM reorder_queue_positions(OLD.release_id);
    END IF;
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create queue maintenance trigger
DROP TRIGGER IF EXISTS queue_position_maintenance ON reservations;
CREATE TRIGGER queue_position_maintenance
  AFTER UPDATE OR DELETE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION maintain_queue_positions();

-- Queue integrity check function
CREATE OR REPLACE FUNCTION verify_queue_integrity(p_release_id bigint)
RETURNS TABLE (
  issue_type text,
  details jsonb
) AS $$
BEGIN
  -- Check for gaps in queue positions
  RETURN QUERY
  WITH position_check AS (
    SELECT 
      position_in_queue,
      LAG(position_in_queue) OVER (ORDER BY position_in_queue) as prev_position
    FROM reservations
    WHERE release_id = p_release_id
      AND status = 'in_queue'
      AND position_in_queue IS NOT NULL
  )
  SELECT 
    'position_gap'::text,
    jsonb_build_object(
      'gap_start', prev_position,
      'gap_end', position_in_queue
    )
  FROM position_check
  WHERE position_in_queue - prev_position > 1
  UNION ALL
  -- Check for invalid status/position combinations
  SELECT
    'invalid_position'::text,
    jsonb_build_object(
      'reservation_id', id,
      'status', status,
      'position', position_in_queue
    )
  FROM reservations
  WHERE release_id = p_release_id
    AND (
      (status = 'in_queue' AND position_in_queue IS NULL) OR
      (status != 'in_queue' AND position_in_queue IS NOT NULL)
    );
END;
$$ LANGUAGE plpgsql;