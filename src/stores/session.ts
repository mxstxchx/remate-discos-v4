import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { SessionState, Language } from '@/types/session'
import { isExpired, addDays, SESSION_EXPIRY_DAYS } from '@/lib/utils'

interface SessionActions {
  setAlias: (alias: string) => void
  setSession: (sessionId: string, expiresAt: Date) => void
  setLanguage: (language: Language) => void
  setAdmin: (isAdmin: boolean) => void
  setDeviceId: (deviceId: string) => void
  clearSession: () => void
  setStatus: (status: SessionState['status']) => void
}

const initialState: SessionState = {
  alias: null,
  sessionId: null,
  language: 'es-ES',
  isAdmin: false,
  deviceId: null,
  expiresAt: null,
  status: 'idle'
}

export const useSessionStore = create(
  persist<SessionState & SessionActions>(
    (set) => ({
      ...initialState,
      setAlias: (alias) => set({ alias }),
      setSession: (sessionId, expiresAt) => set({ sessionId, expiresAt }),
      setLanguage: (language) => set({ language }),
      setAdmin: (isAdmin) => set({ isAdmin }),
      setDeviceId: (deviceId) => set({ deviceId }),
      clearSession: () => set(initialState),
      setStatus: (status) => set({ status })
    }),
    {
      name: 'session-store',
      partialize: (state) => ({
        alias: state.alias,
        sessionId: state.sessionId,
        language: state.language,
        deviceId: state.deviceId
      })
    }
  )
)