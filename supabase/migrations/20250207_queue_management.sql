-- Admin queue management function
CREATE OR REPLACE FUNCTION admin_advance_queue(
  p_release_id bigint,
  p_admin_session_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_next_reservation record;
BEGIN
  -- Verify admin status
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Mark current reservation as sold/cancelled
  UPDATE reservations
  SET status = 'sold'
  WHERE release_id = p_release_id 
  AND status = 'reserved';

  -- Get next in queue
  SELECT * INTO v_next_reservation
  FROM reservations
  WHERE release_id = p_release_id
  AND status = 'in_queue'
  ORDER BY position_in_queue ASC
  LIMIT 1;

  -- Exit if no one in queue
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Update next reservation
  UPDATE reservations
  SET 
    status = 'reserved',
    position_in_queue = NULL,
    updated_at = NOW()
  WHERE id = v_next_reservation.id;

  -- Reorder remaining queue
  UPDATE reservations
  SET position_in_queue = position_in_queue - 1
  WHERE release_id = p_release_id
  AND status = 'in_queue'
  AND position_in_queue > v_next_reservation.position_in_queue;

  -- Log action
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    p_admin_session_id,
    'queue_advanced',
    jsonb_build_object(
      'release_id', p_release_id,
      'new_reservation_id', v_next_reservation.id
    )
  );
END;
$$;