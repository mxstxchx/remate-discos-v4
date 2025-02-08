-- Queue management function
CREATE OR REPLACE FUNCTION manage_queue_position(
  p_release_id bigint,
  p_session_id uuid
) RETURNS TABLE (
  reservation_id uuid,
  queue_position integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_position integer;
  v_reservation_id uuid;
BEGIN
  -- Check if release is available
  IF NOT EXISTS (
    SELECT 1 FROM reservations 
    WHERE release_id = p_release_id 
    AND status IN ('reserved', 'in_cart')
  ) THEN
    -- Direct reservation (no queue needed)
    INSERT INTO reservations (release_id, session_id, status)
    VALUES (p_release_id, p_session_id, 'in_cart')
    RETURNING id INTO v_reservation_id;
    
    RETURN QUERY SELECT v_reservation_id, NULL::integer;
    RETURN;
  END IF;

  -- Add to queue
  SELECT COALESCE(MAX(position_in_queue), 0) + 1
  INTO v_position
  FROM reservations
  WHERE release_id = p_release_id AND status = 'in_queue';

  INSERT INTO reservations (
    release_id,
    session_id,
    status,
    position_in_queue
  ) VALUES (
    p_release_id,
    p_session_id,
    'in_queue',
    v_position
  ) RETURNING id INTO v_reservation_id;

  -- Log action
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    p_session_id,
    'queue_position_assigned',
    jsonb_build_object(
      'release_id', p_release_id,
      'position', v_position
    )
  );

  -- Return reservation info
  RETURN QUERY SELECT v_reservation_id, v_position;
END;
$$;

-- Admin queue advancement
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