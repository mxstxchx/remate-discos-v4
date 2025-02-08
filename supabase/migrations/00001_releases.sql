CREATE TABLE releases (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  artists TEXT[] DEFAULT '{}',
  labels JSONB DEFAULT '[]',
  styles TEXT[] DEFAULT '{}',
  year TEXT,
  country TEXT,
  condition TEXT,
  price DECIMAL(10,2) NOT NULL,
  images JSONB DEFAULT '{}',
  tracklist JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);