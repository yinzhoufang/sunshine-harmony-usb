export interface NativeStats {
  upPkts: number;
  upBytes: number;
  downPkts: number;
  downBytes: number;
  dropped: number;
  sendErrors: number;
  reconnects: number;
  protocolErrors: number;
  videoQueue: number;
  controlQueue: number;
  dispatchP99Us: number;
  videoConnected: number;
  controlConnected: number;
}
export const start: (host: string, videoPort: number, controlPort: number, listenHost: string,
  serverPorts: number[], clientPorts: number[]) => number;
export const stop: () => void;
export const getStats: () => NativeStats;
export const startProbe: () => number;
export const stopProbe: () => void;
