-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Types
CREATE TYPE reservation_status AS ENUM (
  'in_cart',
  'in_queue',
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

-- Basic audit
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Reservations
CREATE TABLE reservations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  release_id BIGINT NOT NULL,
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  status reservation_status NOT NULL DEFAULT 'in_cart',
  position_in_queue INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT valid_queue_position CHECK (
    (status = 'in_queue' AND position_in_queue IS NOT NULL) OR
    (status != 'in_queue' AND position_in_queue IS NULL)
  )
);

-- Indexes
CREATE INDEX idx_sessions_fingerprint ON sessions (fingerprint);
CREATE INDEX idx_reservations_status ON reservations (status, created_at DESC);
CREATE INDEX idx_reservations_queue ON reservations (release_id, position_in_queue) 
  WHERE status = 'in_queue';
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