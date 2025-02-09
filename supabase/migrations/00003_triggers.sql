-- Queue Position Maintenance
CREATE OR REPLACE FUNCTION maintain_queue_positions()
RETURNS TRIGGER AS $$
BEGIN
  -- On queue entry
  IF TG_OP = 'INSERT' AND NEW.status = 'in_queue' THEN
    NEW.position_in_queue := (
      SELECT COALESCE(MAX(position_in_queue), 0) + 1
      FROM reservations
      WHERE release_id = NEW.release_id
      AND status = 'in_queue'
    );
  END IF;

  -- On status change
  IF TG_OP = 'UPDATE' AND OLD.status != NEW.status THEN
    -- Clear position if leaving queue
    IF OLD.status = 'in_queue' THEN
      NEW.position_in_queue := NULL;
      
      -- Reorder remaining queue
      UPDATE reservations
      SET position_in_queue = position_in_queue - 1
      WHERE release_id = NEW.release_id
      AND status = 'in_queue'
      AND position_in_queue > OLD.position_in_queue;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Queue Position Trigger
CREATE TRIGGER queue_positions
  BEFORE INSERT OR UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION maintain_queue_positions();