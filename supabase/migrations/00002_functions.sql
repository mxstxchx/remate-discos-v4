-- Session Management
CREATE OR REPLACE FUNCTION create_session(
  p_device_fingerprint text,
  p_alias text,
  p_language text DEFAULT 'es-ES'
) RETURNS TABLE (
  session_id uuid,
  expires_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_device_id uuid;
  v_session_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Get or create device
  INSERT INTO devices (fingerprint)
  VALUES (p_device_fingerprint)
  ON CONFLICT (fingerprint) 
  DO UPDATE SET last_seen = NOW()
  RETURNING id INTO v_device_id;

  -- Create session
  INSERT INTO sessions (
    device_id,
    alias,
    language,
    expires_at
  ) VALUES (
    v_device_id,
    p_alias,
    p_language,
    NOW() + INTERVAL '30 days'
  )
  RETURNING id, expires_at INTO v_session_id, v_expires_at;

  RETURN QUERY SELECT v_session_id, v_expires_at;
END;
$$;

-- Queue Management
CREATE OR REPLACE FUNCTION manage_queue_position(
  p_release_id bigint
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reservation record;
BEGIN
  -- Check if there are any reservations in queue
  IF NOT EXISTS (
    SELECT 1 FROM reservations 
    WHERE release_id = p_release_id 
    AND status = 'in_queue'
  ) THEN
    RETURN;
  END IF;

  -- Get next in queue
  SELECT * INTO v_reservation
  FROM reservations
  WHERE release_id = p_release_id
  AND status = 'in_queue'
  ORDER BY position_in_queue ASC
  LIMIT 1;

  -- Update to reserved status
  UPDATE reservations
  SET 
    status = 'reserved',
    position_in_queue = NULL,
    expires_at = NOW() + INTERVAL '7 days'
  WHERE id = v_reservation.id;

  -- Reorder remaining queue
  UPDATE reservations
  SET position_in_queue = position_in_queue - 1
  WHERE release_id = p_release_id
  AND status = 'in_queue'
  AND position_in_queue > v_reservation.position_in_queue;

  -- Create audit log
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    v_reservation.session_id,
    'queue_position_updated',
    jsonb_build_object(
      'release_id', p_release_id,
      'reservation_id', v_reservation.id,
      'new_status', 'reserved'
    )
  );
END;
$$;