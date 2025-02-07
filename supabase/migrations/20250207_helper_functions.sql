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

  -- Return session info
  RETURN QUERY SELECT v_session_id, v_expires_at;
END;
$$;

-- Reservation Management
CREATE OR REPLACE FUNCTION create_reservation(
  p_release_id bigint,
  p_session_id uuid
) RETURNS TABLE (
  reservation_id uuid,
  status reservation_status,
  position_in_queue integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reservation_id uuid;
  v_status reservation_status;
  v_position integer;
  v_audit_id uuid;
BEGIN
  -- Check if release is available
  IF EXISTS (
    SELECT 1 FROM reservations 
    WHERE release_id = p_release_id 
    AND status IN ('reserved', 'in_cart')
  ) THEN
    -- Add to queue
    SELECT COALESCE(MAX(position_in_queue), 0) + 1
    INTO v_position
    FROM reservations
    WHERE release_id = p_release_id AND status = 'in_queue';

    v_status := 'in_queue';
  ELSE
    -- Direct reservation
    v_status := 'in_cart';
    v_position := NULL;
  END IF;

  -- Create audit log
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  ) VALUES (
    p_session_id,
    'reservation_created',
    jsonb_build_object(
      'release_id', p_release_id,
      'status', v_status,
      'position', v_position
    )
  ) RETURNING id INTO v_audit_id;

  -- Create reservation
  INSERT INTO reservations (
    release_id,
    session_id,
    status,
    position_in_queue,
    audit_log_id,
    expires_at
  ) VALUES (
    p_release_id,
    p_session_id,
    v_status,
    v_position,
    v_audit_id,
    CASE 
      WHEN v_status = 'in_cart' THEN NOW() + INTERVAL '7 days'
      ELSE NULL
    END
  ) RETURNING id INTO v_reservation_id;

  -- Return reservation info
  RETURN QUERY 
  SELECT v_reservation_id, v_status, v_position;
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

-- Cleanup Functions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Archive expired sessions
  INSERT INTO audit_logs (
    session_id,
    action,
    details
  )
  SELECT 
    id,
    'session_expired',
    jsonb_build_object(
      'alias', alias,
      'device_id', device_id,
      'expired_at', expires_at
    )
  FROM sessions
  WHERE expires_at < NOW();

  -- Delete expired sessions
  DELETE FROM sessions WHERE expires_at < NOW();
END;
$$;

CREATE OR REPLACE FUNCTION cleanup_expired_reservations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_release_id bigint;
BEGIN
  -- Get releases with expired reservations
  FOR v_release_id IN (
    SELECT DISTINCT release_id 
    FROM reservations 
    WHERE status IN ('reserved', 'in_cart')
    AND expires_at < NOW()
  ) LOOP
    -- Update expired reservations
    UPDATE reservations
    SET 
      status = 'expired',
      expires_at = NULL
    WHERE release_id = v_release_id
    AND status IN ('reserved', 'in_cart')
    AND expires_at < NOW();

    -- Create audit logs
    INSERT INTO audit_logs (
      session_id,
      action,
      details
    )
    SELECT
      session_id,
      'reservation_expired',
      jsonb_build_object(
        'release_id', release_id,
        'reservation_id', id,
        'expired_at', expires_at
      )
    FROM reservations
    WHERE release_id = v_release_id
    AND status = 'expired';

    -- Manage queue for this release
    PERFORM manage_queue_position(v_release_id);
  END LOOP;
END;
$$;