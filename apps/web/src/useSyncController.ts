import { useEffect, useRef, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { db, type SyncMeta } from './data'
import { ApiError, api, login, logout, pendingCount, resolveConflict, saveFile, syncOnce } from './sync'

/** Mounted once by App, so navigation never interrupts retry or authentication state. */
export function useSyncController({ editable }: { editable: boolean }) {
  const [needsLogin, setNeedsLogin] = useState(false)
  const [working, setWorking] = useState(false)
  const [status, setStatus] = useState('')
  const [error, setError] = useState('')
  const [lastSyncedAt, setLastSyncedAt] = useState<number | null>(null)
  const [online, setOnline] = useState(navigator.onLine)
  const running = useRef(false), failures = useRef(0), nextAttempt = useRef(0)
  const state = useLiveQuery(async () => ({
    enabled: (await db.syncState.get('enabled'))?.value === 'yes',
    pending: await pendingCount(),
    conflicts: await Promise.all((await db.meta.toArray()).filter(m => m.conflict).map(async meta => ({ meta, local: await db[meta.kind].get(meta.id) }))),
  }))

  async function sync() {
    if (!editable || running.current || (await db.syncState.get('enabled'))?.value !== 'yes') return
    if (!navigator.onLine) { setOnline(false); return }
    // Recheck after the IndexedDB read: an online event and a button can arrive together.
    if (running.current) return
    running.current = true; setWorking(true); setError(''); setStatus('Синхронизация…')
    try {
      const pending = await syncOnce()
      setStatus(pending ? 'Есть изменения, ожидающие отправки' : 'Синхронизировано')
      setLastSyncedAt(Date.now())
      setNeedsLogin(false); failures.current = 0; nextAttempt.current = 0
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) setNeedsLogin(true)
      setError(e instanceof Error ? e.message : 'Не удалось связаться с сервером')
      setStatus(''); failures.current++
      nextAttempt.current = Date.now() + Math.min(300000, 15000 * 2 ** failures.current)
    } finally { running.current = false; setWorking(false) }
  }
  const latest = useRef({ sync, editable, enabled: state?.enabled, needsLogin })
  useEffect(() => { latest.current = { sync, editable, enabled: state?.enabled, needsLogin } })

  useEffect(() => {
    const tick = () => {
      const current = latest.current
      if (current.editable && current.enabled && !current.needsLogin && navigator.onLine && document.visibilityState === 'visible' && Date.now() >= nextAttempt.current) void current.sync()
    }
    const onlineChanged = () => { setOnline(navigator.onLine); if (navigator.onLine) { nextAttempt.current = 0; tick() } }
    const timer = window.setInterval(tick, 30000)
    window.addEventListener('online', onlineChanged); window.addEventListener('offline', onlineChanged)
    document.addEventListener('visibilitychange', tick)
    return () => { clearInterval(timer); window.removeEventListener('online', onlineChanged); window.removeEventListener('offline', onlineChanged); document.removeEventListener('visibilitychange', tick) }
  }, [])

  useEffect(() => {
    if (!editable || !state?.enabled || needsLogin) return
    const timer = window.setTimeout(() => {
      if (document.visibilityState === 'visible' && Date.now() >= nextAttempt.current) void latest.current.sync()
    }, 1200)
    return () => clearTimeout(timer)
  }, [editable, state?.enabled, state?.pending, needsLogin])

  async function action(fn: () => Promise<void>) {
    if (!editable || running.current) return false
    running.current = true; setWorking(true); setError('')
    try { await fn(); return true }
    catch (e) { setError(e instanceof Error ? e.message : 'Ошибка запроса'); return false }
    finally { running.current = false; setWorking(false) }
  }
  return {
    state, working, status, error, online, needsLogin, editable, lastSyncedAt, sync,
    async connect(password: string) {
      const connected = await action(async () => { await login(password); await db.syncState.put({ key: 'enabled', value: 'yes' }); setNeedsLogin(false); setStatus('Вход выполнен') })
      if (connected) await sync()
      return connected
    },
    disconnect: () => action(async () => {
      await navigator.locks.request('traininglog-sync', async () => { await logout(); await db.syncState.put({ key: 'enabled', value: 'no' }) })
      setNeedsLogin(false); setStatus('Вы вышли. Локальные записи сохранены на этом устройстве.')
    }),
    changePassword: (currentPassword: string, newPassword: string) => action(async () => { await api('/auth/password', 'POST', { currentPassword, newPassword }); setStatus('Пароль изменён') }),
    exportServer: () => action(async () => { saveFile(await api('/export'), 'traininglog-server.json'); setStatus('Серверная копия скачана') }),
    downloadConflict: (meta: SyncMeta) => action(async () => saveFile({ local: await db[meta.kind].get(meta.id), remote: meta.remote }, `traininglog-conflict-${meta.id}.json`)),
    async resolve(meta: SyncMeta, choice: 'local' | 'remote') {
      const resolved = await action(async () => { await resolveConflict(meta, choice); setStatus(choice === 'local' ? 'Локальная версия выбрана' : 'Серверная версия принята') })
      if (resolved && choice === 'local') await sync()
    },
    downloadArchive: () => action(async () => saveFile(await db.conflictArchive.toArray(), 'traininglog-conflict-archive.json')),
  }
}

export type SyncController = ReturnType<typeof useSyncController>
