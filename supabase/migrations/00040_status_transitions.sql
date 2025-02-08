CREATE OR REPLACE FUNCTION update_reservation_status(
  p_reservation_id uuid,
  p_new_status reservation_status,
  p_session_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_old_status reservation_status;
  v_release_id bigint;
BEGIN
  -- Get current status
  SELECT status, release_id INTO v_old_status, v_release_id
  FROM reservations WHERE id = p_reservation_id;

  -- Validate transition
  IF NOT (
    (v_old_status = 'in_queue' AND p_new_status IN ('reserved', 'cancelled')) OR
    (v_old_status = 'in_cart' AND p_new_status IN ('reserved', 'cancelled')) OR
    (v_old_status = 'reserved' AND p_new_status IN ('sold', 'cancelled'))
  ) THEN
    RAISE EXCEPTION 'Invalid status transition from % to %', v_old_status, p_new_status;
  END IF;

  -- Update status and clear queue position if needed
  UPDATE reservations
  SET 
    status = p_new_status,
    position_in_queue = CASE 
      WHEN p_new_status != 'in_queue' THEN NULL 
      ELSE position_in_queue 
    END,
    updated_at = NOW()
  WHERE id = p_reservation_id;

  -- Log transition
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    p_session_id,
    'status_updated',
    jsonb_build_object(
      'reservation_id', p_reservation_id,
      'old_status', v_old_status,
      'new_status', p_new_status,
      'release_id', v_release_id
    )
  );

  -- Reorder queue if needed
  IF v_old_status = 'in_queue' THEN
    PERFORM reorder_release_queue(v_release_id);
  END IF;
END;
$$;