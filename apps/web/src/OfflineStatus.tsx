import { useEffect, useRef, useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { activateWaitingWorker, waitForInstallation, withUpdateTimeout } from './appUpdate'

type Props = {
 showCheck: boolean
 blockedReason: string
 beforeReload: () => Promise<void>
 onReloading: (value: boolean) => void
}
type Phase = 'idle' | 'checking' | 'installing' | 'saving' | 'activating'
const labels: Record<Exclude<Phase, 'idle'>, string> = {
 checking: 'Проверяем обновление…', installing: 'Загружаем обновление…',
 saving: 'Сохраняем дневник…', activating: 'Обновляем приложение…',
}
const register = () => navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, {
 scope: import.meta.env.BASE_URL, updateViaCache: 'none',
})

export default function OfflineStatus({ showCheck, blockedReason, beforeReload, onReloading }: Props) {
 const supported = import.meta.env.PROD && 'serviceWorker' in navigator
 const [registration, setRegistration] = useState<ServiceWorkerRegistration | null>(null)
 const [available, setAvailable] = useState(false)
 const [problem, setProblem] = useState(''), [message, setMessage] = useState('')
 const [phase, setPhase] = useState<Phase>('idle')
 const running = useRef(false), reloading = useRef(false), changedElsewhere = useRef(false)

 useEffect(() => {
  if (!supported) return
  let disposed = false
  void register().then(value => { if (!disposed) setRegistration(value) })
   .catch(() => { if (!disposed) setProblem('Офлайн-режим не готов — откройте приложение с интернетом') })
  return () => { disposed = true }
 }, [supported])

 useEffect(() => {
  if (!supported) return
  let previous = navigator.serviceWorker.controller
  const changed = () => {
   const next = navigator.serviceWorker.controller
   if (next === previous) return
   const wasControlled = !!previous
   previous = next
   // First installation needs no reload. Other tabs must not interrupt this tab's input.
   if (!wasControlled) return
   changedElsewhere.current = true
   setAvailable(true)
   if (!reloading.current) setMessage('Новая версия готова. Нажмите «Обновить приложение».')
  }
  navigator.serviceWorker.addEventListener('controllerchange', changed)
  return () => navigator.serviceWorker.removeEventListener('controllerchange', changed)
 }, [supported])

 useEffect(() => {
  if (!registration) return
  const watched = new Set<ServiceWorker>()
  const watch = () => {
   if (registration.waiting) {
    setAvailable(true)
    if (!reloading.current) setMessage('Доступна новая версия приложения')
   }
   const worker = registration.installing
   if (worker && !watched.has(worker)) { watched.add(worker); worker.addEventListener('statechange', watch) }
  }
  const checkOnReturn = () => {
   if (document.visibilityState === 'visible' && navigator.onLine) void registration.update().catch(() => {})
  }
  watch()
  registration.addEventListener('updatefound', watch)
  document.addEventListener('visibilitychange', checkOnReturn)
  window.addEventListener('online', checkOnReturn)
  return () => {
   registration.removeEventListener('updatefound', watch)
   watched.forEach(worker => worker.removeEventListener('statechange', watch))
   document.removeEventListener('visibilitychange', checkOnReturn)
   window.removeEventListener('online', checkOnReturn)
  }
 }, [registration])

 async function update() {
  if (running.current || blockedReason) return
  running.current = true
  let willReload = false
  setProblem(''); setMessage(''); setPhase('checking')
  try {
   const current = registration ?? await register().catch(() => { throw new Error('Не удалось проверить обновление. Проверьте интернет и повторите.') })
   if (!registration) setRegistration(current)
   if (!current.waiting && !changedElsewhere.current) {
    if (!navigator.onLine) throw new Error('Нет интернета. Подключитесь к сети и повторите обновление.')
    await withUpdateTimeout(current.update().catch(() => { throw new Error('Не удалось проверить обновление. Проверьте интернет и повторите.') }), 'Проверка обновления не завершилась. Проверьте интернет и повторите.')
    if (current.installing) { setPhase('installing'); await waitForInstallation(current.installing) }
   }
   if (!current.waiting && !changedElsewhere.current) {
    setAvailable(false); setMessage('Установлена последняя версия'); return
   }
   reloading.current = true
   onReloading(true); setPhase('saving')
   await withUpdateTimeout(beforeReload(), 'Дневник ещё сохраняется. Повторите обновление после сохранения.')
   setPhase('activating')
   await activateWaitingWorker(current)
   willReload = true
   window.location.reload()
  } catch (error) {
   setProblem(error instanceof Error ? error.message : 'Не удалось обновить приложение. Попробуйте ещё раз.')
  } finally {
   if (!willReload) {
    reloading.current = false; running.current = false
    onReloading(false); setPhase('idle')
   }
  }
 }

 if (!supported || (!showCheck && !available && !problem && phase === 'idle')) return null
 return <section className={`app-update ${problem ? 'has-error' : ''}`} aria-label="Обновление приложения" aria-busy={phase !== 'idle'}>
  <p role="status">{phase !== 'idle' ? labels[phase] : problem || message || 'Проверить и установить новую версию приложения'}</p>
  <button type="button" className={available ? 'primary' : 'ghost'} disabled={phase !== 'idle' || !!blockedReason} onClick={() => void update()}>
   <RefreshCw size={18} aria-hidden="true" />{phase === 'idle' ? 'Обновить приложение' : labels[phase]}
  </button>
  {blockedReason && <small>{blockedReason}</small>}
 </section>
}
