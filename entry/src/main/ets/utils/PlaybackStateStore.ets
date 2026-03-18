/**
 * 播放状态持久化工具类
 * 使用 preferences 保存/恢复播放状态
 */

import { preferences } from '@kit.ArkData';

// 存储文件名
const STORE_NAME = 'playback_state';

// Key 常量
const KEY_TRACK_ID = 'last_track_id';
const KEY_TRACK_TITLE = 'last_track_title';
const KEY_TRACK_ARTIST = 'last_track_artist';
const KEY_TRACK_FILE = 'last_track_file';
const KEY_TRACK_DURATION = 'last_track_duration';
const KEY_TRACK_COVER = 'last_track_cover';
const KEY_TRACK_ALBUM = 'last_track_album';
const KEY_POSITION = 'last_position';
const KEY_QUEUE_IDS = 'last_queue_ids';
const KEY_QUEUE_INDEX = 'last_queue_index';
const KEY_PLAY_MODE = 'last_play_mode';

/**
 * 保存的播放状态
 */
export interface SavedPlaybackState {
  trackId: number;
  trackTitle: string;
  trackArtist: string;
  trackFile: string;
  trackDuration: number;
  trackCover: string;
  trackAlbum: string;
  position: number;
  queueIds: string;   // JSON 序列化的 trackId 数组
  queueIndex: number;
  playMode: number;
}

export class PlaybackStateStore {

  /**
   * 保存播放状态
   */
  static async save(context: Context, state: SavedPlaybackState): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      await prefs.put(KEY_TRACK_ID, state.trackId);
      await prefs.put(KEY_TRACK_TITLE, state.trackTitle);
      await prefs.put(KEY_TRACK_ARTIST, state.trackArtist);
      await prefs.put(KEY_TRACK_FILE, state.trackFile);
      await prefs.put(KEY_TRACK_DURATION, state.trackDuration);
      await prefs.put(KEY_TRACK_COVER, state.trackCover);
      await prefs.put(KEY_TRACK_ALBUM, state.trackAlbum);
      await prefs.put(KEY_POSITION, state.position);
      await prefs.put(KEY_QUEUE_IDS, state.queueIds);
      await prefs.put(KEY_QUEUE_INDEX, state.queueIndex);
      await prefs.put(KEY_PLAY_MODE, state.playMode);
      await prefs.flush();
      console.info(`[PlaybackStateStore] 播放状态已保存: ${state.trackTitle}, 进度 ${state.position}ms`);
    } catch (err) {
      console.error('[PlaybackStateStore] 保存播放状态失败');
    }
  }

  /**
   * 读取播放状态，若无记录返回 null
   */
  static async load(context: Context): Promise<SavedPlaybackState | null> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      const trackId = await prefs.get(KEY_TRACK_ID, -1) as number;
      if (trackId < 0) {
        return null;
      }
      const trackTitle = await prefs.get(KEY_TRACK_TITLE, '') as string;
      const trackArtist = await prefs.get(KEY_TRACK_ARTIST, '') as string;
      const trackFile = await prefs.get(KEY_TRACK_FILE, '') as string;
      const trackDuration = await prefs.get(KEY_TRACK_DURATION, 0) as number;
      const trackCover = await prefs.get(KEY_TRACK_COVER, '') as string;
      const trackAlbum = await prefs.get(KEY_TRACK_ALBUM, '') as string;
      const position = await prefs.get(KEY_POSITION, 0) as number;
      const queueIds = await prefs.get(KEY_QUEUE_IDS, '') as string;
      const queueIndex = await prefs.get(KEY_QUEUE_INDEX, 0) as number;
      const playMode = await prefs.get(KEY_PLAY_MODE, 0) as number;

      if (!trackFile) {
        return null;
      }

      return {
        trackId,
        trackTitle,
        trackArtist,
        trackFile,
        trackDuration,
        trackCover,
        trackAlbum,
        position,
        queueIds,
        queueIndex,
        playMode
      };
    } catch (err) {
      console.error('[PlaybackStateStore] 读取播放状态失败');
      return null;
    }
  }

  /**
   * 清除保存的状态
   */
  static async clear(context: Context): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      await prefs.clear();
      await prefs.flush();
    } catch (err) {
      console.error('[PlaybackStateStore] 清除播放状态失败');
    }
  }
}
