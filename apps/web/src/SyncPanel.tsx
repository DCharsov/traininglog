import { useState } from 'react'
import { conflictDifferences } from './conflictComparison'
import type { SyncController } from './useSyncController'
import './settings.css'

function serverMessage(controller: SyncController) {
  const { state, needsLogin, online, working, error, lastSyncedAt } = controller
  if (!state) return 'Проверяем состояние сохранения…'
  if (!state.enabled) return 'Серверная копия не подключена'
  if (needsLogin) return 'Для отправки нужен вход'
  if (state.conflicts.length) return `Нужно выбрать версию: ${state.conflicts.length}`
  if (!online) return state.pending ? `Нет сети · ожидают отправки: ${state.pending}` : 'Нет сети · серверная копия обновится при подключении'
  if (working) return 'Синхронизация…'
  if (error) return 'Отправка не удалась · повторим автоматически'
  if (state.pending) return `Ожидают отправки: ${state.pending}`
  return lastSyncedAt ? 'Синхронизировано' : 'Проверяем синхронизацию…'
}

export function SyncStatus({ controller, localStatus, onOpen }: { controller: SyncController; localStatus?: string; onOpen: () => void }) {
  return <button className={`sync-status ${controller.error || controller.needsLogin || controller.state?.conflicts.length ? 'needs-attention' : ''}`} onClick={onOpen} aria-label="Состояние сохранения и синхронизации">
    <span>{localStatus ?? `На устройстве: ${controller.state ? 'сохранено' : 'проверяем…'}`}</span>
    <small>{serverMessage(controller)}</small>
  </button>
}

export default function SyncPanel({ controller, expanded = true }: { controller: SyncController; expanded?: boolean }) {
  const [password, setPassword] = useState(''), [newPassword, setNewPassword] = useState('')
  const { state, needsLogin, editable, working, status, error } = controller
  const disabled = !editable || working
  return <section className="card sync-panel">
    <h2>Синхронизация</h2>
    <p>На устройстве: {state ? 'изменения сохранены' : 'проверяем сохранение…'}. Можно пользоваться дневником без сети.</p>
    <p aria-live="polite">{serverMessage(controller)}</p>
    {!!status && status !== serverMessage(controller) && <p role="status">{status}</p>}
    {!!error && <p className="field-error" role="alert">{error}</p>}
    {state?.enabled && <button disabled={disabled} onClick={() => void controller.sync()}>Синхронизировать сейчас</button>}
    {expanded && ((!state?.enabled || needsLogin) ? <form onSubmit={e => { e.preventDefault(); void controller.connect(password).then(ok => { if (ok) setPassword('') }) }}>
      <h3>Вход владельца</h3><p>Программы и тренировки этого браузера будут синхронизироваться с вашим серверным дневником.</p>
      <label>Пароль<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required maxLength={256} /></label>
      <button className="primary" disabled={disabled}>Войти и подключить синхронизацию</button>
    </form> : <>
      <p>На другом устройстве откройте тот же адрес и войдите с тем же паролем. Синхронизация работает во всех разделах приложения; записи без сети отправятся после подключения.</p>
      <button disabled={disabled} onClick={() => void controller.disconnect()}>Выйти, сохранив локальный дневник</button>
      <button disabled={disabled} onClick={() => void controller.exportServer()}>Скачать серверный JSON</button>
      <details><summary>Изменить пароль</summary><form onSubmit={e => { e.preventDefault(); void controller.changePassword(password, newPassword).then(ok => { if (ok) { setPassword(''); setNewPassword('') } }) }}>
        <label>Текущий пароль<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
        <label>Новый пароль<input type="password" autoComplete="new-password" value={newPassword} onChange={e => setNewPassword(e.target.value)} minLength={12} maxLength={256} required /></label>
        <p>От 12 символов, заглавная и строчная буквы, цифра и спецсимвол.</p><button disabled={disabled}>Изменить пароль</button>
      </form></details>
    </>)}
    {!!state?.conflicts.length && <div className="sync-conflicts">
      <h3>Сравните изменения</h3><p>Выбранная версия станет общей. Обе версии останутся в локальном архиве конфликтов.</p>
      {state.conflicts.map(({ meta, local }) => {
        const differences = conflictDifferences(meta.kind, local, meta.remote)
        return <article className="conflict-card" key={meta.key}>
          <h3>{meta.remote?.name ?? local?.name ?? 'Запись дневника'}</h3>
          {!local && <p>Этой записи ещё нет на устройстве.</p>}
          {differences.length ? <dl className="conflict-differences">{differences.map((difference, index) => <div key={index}>
            <dt>{difference.label}</dt><dd><span>На устройстве</span>{difference.local}</dd><dd><span>На сервере</span>{difference.remote}</dd>
          </div>)}</dl> : <p>Содержимое совпадает. Отличаются служебные данные записи.</p>}
          <div className="actions"><button disabled={disabled || !local} onClick={() => void controller.resolve(meta, 'local')}>Оставить локальную</button><button disabled={disabled} onClick={() => void controller.resolve(meta, 'remote')}>Принять серверную</button></div>
          <button className="ghost" disabled={disabled} onClick={() => void controller.downloadConflict(meta)}>Скачать обе версии</button>
        </article>
      })}
    </div>}
    {expanded && <button disabled={disabled} onClick={() => void controller.downloadArchive()}>Скачать архив разрешённых конфликтов</button>}
  </section>
}
