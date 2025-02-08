-- Status transition with queue position handling
CREATE OR REPLACE FUNCTION update_reservation_status(
  p_reservation_id uuid,
  p_new_status reservation_status,
  p_admin_session_id uuid DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_current_status reservation_status;
  v_release_id bigint;
  v_session_id uuid;
BEGIN
  -- Lock reservation and get current state
  SELECT status, release_id, session_id
  INTO v_current_status, v_release_id, v_session_id
  FROM reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  -- Validate transition
  IF NOT EXISTS (
    SELECT 1 FROM get_allowed_transitions(v_current_status) 
    WHERE next_status = p_new_status
  ) THEN
    RAISE EXCEPTION 'Invalid status transition: % to %', 
      v_current_status, p_new_status;
  END IF;

  -- Update status (trigger handles position)
  UPDATE reservations
  SET 
    status = p_new_status,
    updated_at = NOW()
  WHERE id = p_reservation_id;

  -- Log the update
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    COALESCE(p_admin_session_id, v_session_id),
    'update_reservation_status',
    jsonb_build_object(
      'reservation_id', p_reservation_id,
      'old_status', v_current_status,
      'new_status', p_new_status,
      'is_admin_action', p_admin_session_id IS NOT NULL
    )
  );

  -- Run integrity check
  PERFORM verify_queue_integrity(v_release_id);
END;
$$ LANGUAGE plpgsql;

-- Optimized batch cancellation
CREATE OR REPLACE FUNCTION cancel_reservations(
  p_release_id bigint,
  p_admin_session_id uuid,
  p_status_filter reservation_status[] DEFAULT NULL
) RETURNS TABLE (
  reservation_id uuid,
  old_status reservation_status,
  success boolean,
  message text
) AS $$
DECLARE
  v_reservation RECORD;
BEGIN
  -- Lock all matching reservations
  FOR v_reservation IN
    SELECT id, status
    FROM reservations
    WHERE release_id = p_release_id
      AND (p_status_filter IS NULL OR status = ANY(p_status_filter))
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM update_reservation_status(
        v_reservation.id,
        'cancelled'::reservation_status,
        p_admin_session_id
      );

      RETURN QUERY
      SELECT 
        v_reservation.id,
        v_reservation.status,
        true,
        'Successfully cancelled'::text;
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY
      SELECT 
        v_reservation.id,
        v_reservation.status,
        false,
        SQLERRM::text;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql;