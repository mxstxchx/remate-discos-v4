import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function isExpired(date: Date | null): boolean {
  if (!date) return true
  return new Date() > new Date(date)
}

export function generateFallbackId(): string {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
}

export function formatPrice(amount: number): string {
  return new Intl.NumberFormat('es-ES', {
    style: 'currency',
    currency: 'EUR'
  }).format(amount)
}

export function getUnixTime(): number {
  return Math.floor(Date.now() / 1000)
}

export function addDays(date: Date, days: number): Date {
  const result = new Date(date)
  result.setDate(result.getDate() + days)
  return result
}

export const RESERVATION_EXPIRY_DAYS = 7
export const SESSION_EXPIRY_DAYS = 30