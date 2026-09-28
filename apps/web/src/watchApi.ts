import { api } from './sync'
import type { WatchControl } from './data'
import type { Session } from './domain'

export type WatchSnapshot={protocolVersion:1;contractVersion:2;sessionId:string;version:number;generation:string;control:Pick<WatchControl,'state'|'deviceId'|'controlEpoch'|'handoffId'>;payload:Session}
export type WatchDevice={id:string;name:string;expiresAt:number;revokedAt:number|null;lastSeenAt:number}
export const getWatchDevices=()=>api<{enabled:boolean;devices:WatchDevice[]}>('/watch/devices')
export const getWatchControl=(id:string)=>api<WatchSnapshot>(`/sessions/${id}/watch-control`)
