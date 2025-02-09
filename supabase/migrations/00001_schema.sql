-- Types
CREATE TYPE reservation_status AS ENUM (
  'available',
  'in_cart',
  'in_queue',
  'reserved',
  'sold',
  'expired',
  'cancelled'
);

-- Base tables
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

CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  device_id UUID NOT NULL,
  alias TEXT NOT NULL,
  language TEXT DEFAULT 'es-ES',
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_active TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  CONSTRAINT valid_expiry CHECK (expires_at > created_at)
);

CREATE TABLE reservations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  release_id BIGINT REFERENCES releases(id),
  session_id UUID REFERENCES sessions(id),
  status reservation_status NOT NULL,
  position_in_queue INTEGER,
  reserved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  audit_log_id UUID REFERENCES audit_logs(id),
  CONSTRAINT valid_queue_position CHECK (
    (status = 'in_queue' AND position_in_queue IS NOT NULL) OR
    (status != 'in_queue' AND position_in_queue IS NULL)
  )
);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id),
  action TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);