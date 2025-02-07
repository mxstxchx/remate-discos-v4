'use client'

import { FC, ReactNode, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { BroadcastChannel } from 'broadcast-channel'
import { useSessionStore } from '@/stores/session'
import { isExpired } from '@/lib/utils'

interface Props {
  children: ReactNode
}

const channel = new BroadcastChannel('session-sync')

export const SessionProvider: FC<Props> = ({ children }) => {
  const [mounted, setMounted] = useState(false)
  const router = useRouter()
  const session = useSessionStore()

  useEffect(() => {
    if (!mounted) {
      setMounted(true)

      // Check session validity
      if (session.sessionId && isExpired(session.expiresAt)) {
        session.clearSession()
        router.replace('/session')
        return
      }
    }

    // Set up cross-tab sync
    channel.onmessage = (event: { type: string; payload?: any }) => {
      switch (event.type) {
        case 'session:expired':
          session.clearSession()
          router.replace('/session')
          break
        case 'session:updated':
          if (event.payload) {
            session.setSession(event.payload.sessionId, event.payload.expiresAt)
          }
          break
      }
    }

    return () => {
      channel.close()
    }
  }, [mounted, session, router])

  if (!mounted) return null

  return <>{children}</>
}

export default SessionProvider