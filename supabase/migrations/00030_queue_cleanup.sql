-- Queue cleanup functions
CREATE OR REPLACE FUNCTION reorder_release_queue(
  p_release_id bigint
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_position integer := 1;
  v_reservation record;
BEGIN
  -- Reassign positions sequentially
  FOR v_reservation IN (
    SELECT id 
    FROM reservations
    WHERE release_id = p_release_id
    AND status = 'in_queue'
    ORDER BY position_in_queue ASC
  ) LOOP
    UPDATE reservations 
    SET position_in_queue = v_position
    WHERE id = v_reservation.id;
    
    v_position := v_position + 1;
  END LOOP;
END;
$$;

-- Batch cancel reservations
CREATE OR REPLACE FUNCTION admin_cancel_reservations(
  p_release_id bigint,
  p_session_ids uuid[],
  p_admin_session_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Verify admin status
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Cancel reservations
  UPDATE reservations
  SET 
    status = 'cancelled',
    position_in_queue = NULL,
    updated_at = NOW()
  WHERE release_id = p_release_id
  AND session_id = ANY(p_session_ids);

  -- Log action
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    p_admin_session_id,
    'reservations_cancelled',
    jsonb_build_object(
      'release_id', p_release_id,
      'sessions', p_session_ids
    )
  );

  -- Reorder remaining queue
  PERFORM reorder_release_queue(p_release_id);
END;
$$;