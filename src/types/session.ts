export type Language = 'es-ES' | 'en-UK'

export interface Device {
  id: string
  fingerprint: string
  last_seen: Date
  is_active: boolean
}

export interface Session {
  id: string
  alias: string
  device_id: string
  language: Language
  is_admin: boolean
  created_at: Date
  last_active: Date
  expires_at: Date
}

export type SessionStatus = 'idle' | 'loading' | 'error'

export interface SessionState {
  alias: string | null
  sessionId: string | null
  language: Language
  isAdmin: boolean
  deviceId: string | null
  expiresAt: Date | null
  status: SessionStatus
}