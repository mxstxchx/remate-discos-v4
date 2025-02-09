-- Queue Position Management
CREATE OR REPLACE FUNCTION manage_queue_positions()
RETURNS TRIGGER AS $$
BEGIN
    -- Handle position assignment/cleanup
    IF NEW.status = 'in_queue' THEN
        NEW.position_in_queue := (
            SELECT COUNT(*) + 1
            FROM reservations 
            WHERE release_id = NEW.release_id
            AND status = 'in_queue'
            AND (position_in_queue < COALESCE(OLD.position_in_queue, 2147483647))
        );
    ELSE
        NEW.position_in_queue := NULL;
        -- Compact remaining positions
        UPDATE reservations
        SET position_in_queue = r.new_pos
        FROM (
            SELECT id, ROW_NUMBER() OVER (ORDER BY position_in_queue) as new_pos
            FROM reservations
            WHERE release_id = NEW.release_id
            AND status = 'in_queue'
            AND id != NEW.id
        ) r
        WHERE reservations.id = r.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS queue_positions ON reservations;
CREATE TRIGGER queue_positions
  BEFORE INSERT OR UPDATE ON reservations
  FOR EACH ROW 
  EXECUTE FUNCTION manage_queue_positions();