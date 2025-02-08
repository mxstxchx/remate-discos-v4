-- Test data
INSERT INTO sessions (id, fingerprint, alias, expires_at) VALUES 
('123e4567-e89b-12d3-a456-426614174000', 'test-fp-1', 'Test User 1', NOW() + INTERVAL '30 days'),
('123e4567-e89b-12d3-a456-426614174001', 'test-fp-2', 'Test User 2', NOW() + INTERVAL '30 days');