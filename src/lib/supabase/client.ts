import { createBrowserClient } from '@supabase/ssr'
import { Device, Session } from '@/types/session'
import { Release, Reservation } from '@/types/release'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const createClient = () => {
  return createBrowserClient<{
    devices: Device
    sessions: Session
    releases: Release
    reservations: Reservation
  }>(supabaseUrl, supabaseKey)
}

export type SupabaseClient = ReturnType<typeof createClient>