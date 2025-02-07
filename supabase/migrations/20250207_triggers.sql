-- Update timestamps trigger
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_releases_timestamp
  BEFORE UPDATE ON releases
  FOR EACH ROW
  EXECUTE FUNCTION update_timestamp();

-- Session activity trigger
CREATE OR REPLACE FUNCTION update_session_activity()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_active = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_session_activity_timestamp
  BEFORE UPDATE ON sessions
  FOR EACH ROW
  EXECUTE FUNCTION update_session_activity();

-- Reservation status change trigger
CREATE OR REPLACE FUNCTION audit_reservation_status()
RETURNS TRIGGER AS $$
DECLARE
  v_audit_id uuid;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    -- Create audit log
    INSERT INTO audit_logs (
      session_id,
      action,
      details
    ) VALUES (
      NEW.session_id,
      'reservation_status_changed',
      jsonb_build_object(
        'release_id', NEW.release_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'changed_at', NOW()
      )
    ) RETURNING id INTO v_audit_id;

    -- Update audit log reference
    NEW.audit_log_id = v_audit_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_reservation_status_change
  BEFORE UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION audit_reservation_status();

-- Queue position validation trigger
CREATE OR REPLACE FUNCTION validate_queue_position()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure queue positions are continuous
  IF NEW.status = 'in_queue' AND NEW.position_in_queue IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 
      FROM reservations 
      WHERE release_id = NEW.release_id 
      AND status = 'in_queue'
      AND position_in_queue >= NEW.position_in_queue
    ) THEN
      -- Shift existing positions
      UPDATE reservations
      SET position_in_queue = position_in_queue + 1
      WHERE release_id = NEW.release_id
      AND status = 'in_queue'
      AND position_in_queue >= NEW.position_in_queue;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_queue_position_change
  BEFORE INSERT OR UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION validate_queue_position();

-- Status transition validation trigger
CREATE OR REPLACE FUNCTION validate_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Define valid transitions
  IF NOT (
    (OLD.status = 'available' AND NEW.status IN ('in_cart')) OR
    (OLD.status = 'in_cart' AND NEW.status IN ('reserved', 'available')) OR
    (OLD.status = 'reserved' AND NEW.status IN ('sold', 'expired', 'cancelled')) OR
    (OLD.status = 'in_queue' AND NEW.status IN ('reserved')) OR
    (OLD.status IN ('expired', 'cancelled') AND NEW.status IN ('available'))
  ) THEN
    RAISE EXCEPTION 'Invalid status transition from % to %', OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_status_transition_change
  BEFORE UPDATE ON reservations
  FOR EACH ROW
  EXECUTE FUNCTION validate_status_transition();