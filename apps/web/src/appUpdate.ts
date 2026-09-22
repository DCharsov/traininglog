/** The update check may finish before the new worker has cached all offline files. */
export function waitForInstallation(worker: ServiceWorker, timeoutMs = 30000): Promise<void> {
 return new Promise((resolve, reject) => {
  const finish = (error?: Error) => {
   clearTimeout(timer)
   worker.removeEventListener('statechange', changed)
   if (error) reject(error); else resolve()
  }
  const changed = () => {
   if (['installed', 'activating', 'activated'].includes(worker.state)) finish()
   else if (worker.state === 'redundant') finish(new Error('Не удалось загрузить обновление. Проверьте интернет и повторите.'))
  }
  const timer = setTimeout(() => finish(new Error('Обновление ещё загружается. Повторите после восстановления связи.')), timeoutMs)
  worker.addEventListener('statechange', changed)
  changed()
 })
}

export function withUpdateTimeout<T>(task: Promise<T>, message: string, timeoutMs = 20000): Promise<T> {
 return new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(message)), timeoutMs)
  task.then(value => { clearTimeout(timer); resolve(value) }, error => { clearTimeout(timer); reject(error) })
 })
}

/** Reload only after the new worker actually controls this page. */
export function activateWaitingWorker(registration: ServiceWorkerRegistration): Promise<void> {
 const waiting = registration.waiting
 if (!waiting) return Promise.resolve()
 const workers = navigator.serviceWorker
 const previous = workers.controller
 return new Promise((resolve, reject) => {
  const finish = (error?: Error) => {
   clearTimeout(timer)
   workers.removeEventListener('controllerchange', changed)
   if (error) reject(error); else resolve()
  }
  const changed = () => { if (workers.controller && workers.controller !== previous) finish() }
  const timer = setTimeout(() => finish(new Error('Обновление не применилось. Попробуйте ещё раз.')), 20000)
  workers.addEventListener('controllerchange', changed)
  try {
   waiting.postMessage({ type: 'TRAININGLOG_APPLY_UPDATE' })
   changed()
  } catch { finish(new Error('Не удалось применить обновление. Попробуйте ещё раз.')) }
 })
}
