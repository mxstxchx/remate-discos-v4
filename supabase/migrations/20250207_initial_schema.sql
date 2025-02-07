-- Create custom types
CREATE TYPE reservation_status AS ENUM (
  'available',
  'in_cart',
  'reserved',
  'in_queue',
  'sold',
  'expired',
  'cancelled'
);

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Devices table
CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  fingerprint TEXT NOT NULL UNIQUE,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE
);

-- Sessions table
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
  alias TEXT NOT NULL,
  language TEXT DEFAULT 'es-ES',
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_active TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT valid_language CHECK (language IN ('es-ES', 'en-UK'))
);

-- Releases table
CREATE TABLE releases (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  artists TEXT[] NOT NULL,
  labels JSONB NOT NULL,
  styles TEXT[] NOT NULL,
  year TEXT,
  country TEXT,
  condition TEXT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  images JSONB NOT NULL,
  tracklist JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Reservations table
CREATE TABLE reservations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  release_id BIGINT REFERENCES releases(id) ON DELETE CASCADE,
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  status reservation_status NOT NULL DEFAULT 'available',
  position_in_queue INTEGER,
  reserved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  audit_log_id UUID,
  CONSTRAINT valid_queue_position CHECK (
    (status = 'in_queue' AND position_in_queue IS NOT NULL) OR
    (status != 'in_queue' AND position_in_queue IS NULL)
  )
);

-- Audit logs table
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add audit_log reference after both tables exist
ALTER TABLE reservations 
  ADD CONSTRAINT fk_audit_log 
  FOREIGN KEY (audit_log_id) 
  REFERENCES audit_logs(id);

-- Indexes
CREATE INDEX idx_devices_fingerprint ON devices (fingerprint);
CREATE INDEX idx_sessions_device ON sessions (device_id, expires_at DESC);
CREATE INDEX idx_sessions_alias ON sessions (alias);
CREATE INDEX idx_releases_title ON releases USING gin (to_tsvector('spanish', title));
CREATE INDEX idx_releases_artists ON releases USING gin (artists);
CREATE INDEX idx_releases_labels ON releases USING gin (labels);
CREATE INDEX idx_releases_styles ON releases USING gin (styles);
CREATE INDEX idx_reservations_status ON reservations (status, reserved_at DESC);
CREATE INDEX idx_audit_logs_session ON audit_logs (session_id, created_at DESC);

-- RLS Policies
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Device policies
CREATE POLICY "Devices viewable by matching fingerprint"
  ON devices FOR SELECT
  USING (fingerprint = current_setting('app.device_fingerprint')::text);

CREATE POLICY "Devices creatable by all"
  ON devices FOR INSERT
  WITH CHECK (true);

-- Session policies
CREATE POLICY "Sessions viewable by device"
  ON sessions FOR SELECT
  USING (device_id IN (
    SELECT id FROM devices 
    WHERE fingerprint = current_setting('app.device_fingerprint')::text
  ));

CREATE POLICY "Sessions manageable by device"
  ON sessions FOR ALL
  USING (device_id IN (
    SELECT id FROM devices 
    WHERE fingerprint = current_setting('app.device_fingerprint')::text
  ));

-- Release policies
CREATE POLICY "Releases viewable by all"
  ON releases FOR SELECT
  USING (true);

CREATE POLICY "Releases manageable by admin"
  ON releases FOR ALL
  USING (EXISTS (
    SELECT 1 FROM sessions 
    WHERE id = current_setting('app.session_id')::uuid
    AND is_admin = true
  ));

-- Reservation policies
CREATE POLICY "Reservations viewable by session"
  ON reservations FOR SELECT
  USING (session_id = current_setting('app.session_id')::uuid);

CREATE POLICY "Reservations manageable by session"
  ON reservations FOR ALL
  USING (session_id = current_setting('app.session_id')::uuid);

-- Audit log policies
CREATE POLICY "Audit logs viewable by admin"
  ON audit_logs FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM sessions 
    WHERE id = current_setting('app.session_id')::uuid
    AND is_admin = true
  ));