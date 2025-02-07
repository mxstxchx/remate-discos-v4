export interface Release {
  id: number
  title: string
  artists: string[]
  labels: { name: string; catno: string }[]
  styles: string[]
  year?: string
  country?: string
  condition: string
  price: number
  images: {
    primary: string
    secondary?: string
  }
  tracklist?: {
    position: string
    title: string
    duration?: string
  }[]
}

export type ReservationStatus =
  | 'available'
  | 'in_cart'
  | 'reserved'
  | 'in_queue'
  | 'sold'
  | 'expired'
  | 'cancelled'

export interface Reservation {
  id: string
  release_id: number
  session_id: string
  status: ReservationStatus
  position_in_queue?: number
  reserved_at: Date
  expires_at?: Date
  audit_log_id: string
}