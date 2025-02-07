-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Types
CREATE TYPE reservation_status AS ENUM (
  'in_cart',
  'reserved',
  'sold',
  'cancelled'
);

-- Helper function
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN current_setting('app.is_admin', TRUE)::boolean;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Sessions
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  fingerprint TEXT NOT NULL,
  alias TEXT NOT NULL,
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  CONSTRAINT valid_expiry CHECK (expires_at > created_at)
);

-- Reservations
CREATE TABLE reservations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  release_id BIGINT NOT NULL,
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  status reservation_status NOT NULL DEFAULT 'in_cart',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Basic audit
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_sessions_fingerprint ON sessions (fingerprint);
CREATE INDEX idx_reservations_status ON reservations (status, created_at DESC);
CREATE INDEX idx_audit_session ON audit_logs (session_id, created_at DESC);

-- RLS
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Session policies
CREATE POLICY "Sessions readable by fingerprint"
  ON sessions FOR SELECT
  USING (fingerprint = current_setting('app.device_fingerprint', TRUE));

CREATE POLICY "Sessions insertable by all"
  ON sessions FOR INSERT
  WITH CHECK (TRUE);

-- Reservation policies
CREATE POLICY "Reservations viewable by session"
  ON reservations FOR SELECT
  USING (
    session_id = current_setting('app.session_id', TRUE)::uuid OR
    is_admin()
  );

CREATE POLICY "Reservations manageable by session"
  ON reservations FOR ALL
  USING (
    session_id = current_setting('app.session_id', TRUE)::uuid OR
    is_admin()
  );

-- Audit policies
CREATE POLICY "Audit logs viewable by admin"
  ON audit_logs FOR SELECT
  USING (is_admin());

-- Helper function
CREATE OR REPLACE FUNCTION create_session(
  p_fingerprint text,
  p_alias text
) RETURNS TABLE (
  session_id uuid,
  expires_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session_id uuid;
  v_expires_at timestamptz;
BEGIN
  INSERT INTO sessions (
    fingerprint,
    alias,
    expires_at
  ) VALUES (
    p_fingerprint,
    p_alias,
    NOW() + INTERVAL '30 days'
  )
  RETURNING id, expires_at INTO v_session_id, v_expires_at;

  RETURN QUERY SELECT v_session_id, v_expires_at;
END;
$$;