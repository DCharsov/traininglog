import { useState } from 'react'
import { Download } from 'lucide-react'
import { db, download, exportData, restore } from './data'
import { backupSchema, type Backup, type Program } from './domain'
import SeedPrograms from './SeedPrograms'
import { downloadCsv } from './progress'
import ManageData from './ManageData'
import SyncPanel from './SyncPanel'
import type { SyncController } from './useSyncController'
import './settings.css'

export type SettingsSection = 'sync' | 'equipment' | 'archive' | 'backup' | 'programs'
const sections: { id: SettingsSection; name: string; detail: string }[] = [
 { id: 'sync', name: 'Синхронизация', detail: 'Серверная копия, вход и выбор версий' },
 { id: 'equipment', name: 'Оборудование', detail: 'Учёт веса, шаг и доступные веса' },
 { id: 'archive', name: 'Архив и корзина', detail: 'Поиск и восстановление скрытых записей' },
 { id: 'backup', name: 'Резервные копии', detail: 'Скачать дневник или восстановить из файла' },
 { id: 'programs', name: 'Готовые программы', detail: 'Добавить программу в дневник' },
]
type Props = {
 disabled: boolean; editable: boolean; programs: Program[]; program?: Program; sync: SyncController
 run: (action: () => Promise<unknown>, message?: string) => Promise<boolean>
 refresh: () => void; onSelectProgram: (id: string) => void; ask: (text: string, confirm?: string) => Promise<boolean>
 section?: SettingsSection | null; onSectionChange?: (section: SettingsSection | null) => void
}
export default function SettingsScreen({ disabled, programs, program, sync, run, refresh, onSelectProgram, ask, section: controlledSection, onSectionChange }: Props) {
 const [imported, setImported] = useState<Backup | null>(null)
 const [localSection, setLocalSection] = useState<SettingsSection | null>(null)
 const section = onSectionChange ? controlledSection ?? null : localSection
 const select = (value: SettingsSection | null) => { if (onSectionChange) onSectionChange(value); else setLocalSection(value) }
 const manageSection = section === 'equipment' || section === 'archive' ? section : undefined
 return <div className="settings-screen">
  {section ? <button className="settings-back" onClick={() => select(null)}>← Все настройки</button> : <section className="card">
   <h2>Настройки</h2><div className="settings-menu">{sections.map(item => <button key={item.id} aria-label={item.name} onClick={() => select(item.id)}><strong>{item.name}</strong><span>{item.detail}</span></button>)}</div>
  </section>}
  <div hidden={section !== 'sync'}><SyncPanel controller={sync} expanded /></div>
  <section className="card" hidden={section !== 'programs'}><h2>Готовые программы</h2><SeedPrograms disabled={disabled} programs={programs} program={program} run={run} onSelectProgram={onSelectProgram} refresh={refresh} /></section>
  <div hidden={!manageSection}><ManageData disabled={disabled} run={run} ask={ask} section={manageSection ?? 'equipment'} /></div>
  <section className="card" hidden={section !== 'backup'}>
   <h2>Резервные копии</h2><p>JSON сохраняет весь дневник для восстановления. CSV подходит для просмотра подходов в таблице.</p>
   <div className="actions"><button onClick={() => void run(async () => download(await exportData()), 'Копия скачана')}><Download size={18} /> JSON</button><button onClick={() => void run(async () => downloadCsv(await db.sessions.toArray()), 'CSV скачан')}>CSV всех подходов</button></div>
   <details><summary>Восстановить из JSON</summary><p>Восстановление заменит весь локальный дневник. Текущие записи скачаются перед заменой.</p>
    <input aria-label="Файл резервной копии" disabled={disabled} type="file" accept="application/json,.json" onChange={e => {
     const file = e.target.files?.[0]
     if (file) void run(async () => { if (file.size > 20 * 1024 * 1024) throw new Error('Файл больше 20 МБ.'); setImported(backupSchema.parse(JSON.parse(await file.text()))) }, 'Файл проверен')
     e.target.value = ''
    }} />
    {imported && <div className="import-preview"><p>В файле: {imported.programs.length} программ, {imported.sessions.length} тренировок.</p><button className="primary" disabled={disabled} onClick={() => void run(async () => { download(await exportData(), 'traininglog-before-restore'); await restore(imported); setImported(null); refresh() }, 'Дневник восстановлен')}>Скачать текущую копию и заменить</button><button className="ghost" onClick={() => setImported(null)}>Отмена</button></div>}
   </details>
  </section>
 </div>
}
