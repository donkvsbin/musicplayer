/**
 * 应用全局常量定义
 */

// 数据库配置
export const DATABASE_NAME = 'music_player.db';
export const DATABASE_VERSION = 1;

// 表名常量
export const TRACK_TABLE = 'track';
export const PLAYLIST_TABLE = 'playlist';
export const PLAYLIST_TRACK_TABLE = 'playlist_track';

export const SEARCH_HISTORY_TABLE = 'search_history'

// 默认路径
export const DEFAULT_COVER_PATH = '';

// 音频文件扩展名
export const AUDIO_EXTENSIONS = ['.mp3', '.flac', '.m4a', '.wav', '.aac', '.ogg', '.wma'];

// 扫描批次大小
export const SCAN_BATCH_SIZE = 50;

// 播放列表默认名称
export const DEFAULT_PLAYLIST_FAVORITE = '我喜欢的音乐';
export const DEFAULT_PLAYLIST_RECENT = '最近播放';

// 错误码
export enum ErrorCode {
  SUCCESS = 0,
  DATABASE_ERROR = 1001,
  PLAYER_ERROR = 2001,
  FILE_NOT_FOUND = 3001,
  PERMISSION_DENIED = 4001,
  UNKNOWN_ERROR = 9999
}

// 播放模式
export enum PlayMode {
  ORDER = 0,      // 顺序播放
  RANDOM = 1,     // 随机播放
  SINGLE_LOOP = 2 // 单曲循环
}

// 播放器状态
export enum PlayerState {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARING = 'preparing',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  STOPPED = 'stopped',
  ERROR = 'error',
  RELEASED = 'released'
}

// 存储键名接口
export interface StorageKeys {
  PLAY_MODE: string;
  LAST_TRACK_ID: string;
  LAST_POSITION: string;
  VOLUME: string;
}

// 存储键名
export const STORAGE_KEYS: StorageKeys = {
  PLAY_MODE: 'play_mode',
  LAST_TRACK_ID: 'last_track_id',
  LAST_POSITION: 'last_position',
  VOLUME: 'volume'
};

// 事件名称接口
export interface EventNames {
  TRACK_CHANGED: string;
  PLAY_STATE_CHANGED: string;
  PROGRESS_UPDATED: string;
  SCAN_PROGRESS: string;
  SCAN_COMPLETED: string;
}

// 事件名称
export const EVENT_NAMES: EventNames = {
  TRACK_CHANGED: 'track_changed',
  PLAY_STATE_CHANGED: 'play_state_changed',
  PROGRESS_UPDATED: 'progress_updated',
  SCAN_PROGRESS: 'scan_progress',
  SCAN_COMPLETED: 'scan_completed'
};
