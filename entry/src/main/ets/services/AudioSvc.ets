/**
 * 音频服务类
 * 封装 AVPlayer 实现音乐播放控制
 * 管理播放状态机、播放列表和播放模式
 */

import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { emitter } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { TrackInfo } from '../models/TrackInfo';
import { PlayerState, PlayMode } from '../constants/AppConstants';
import { SavedPlaybackState } from '../utils/PlaybackStateStore';

/**
 * 播放进度信息
 */
export interface ProgressInfo {
  currentTime: number;
  duration: number;
  progress: number; // 0-1
}

/**
 * 音频服务（单例模式）
 */
export class AudioSvc {
  private static instance: AudioSvc;
  private avPlayer: media.AVPlayer | null = null;
  private avSession: avSession.AVSession | null = null;
  // 播放状态
  private currentState: PlayerState = PlayerState.IDLE;
  private currentTrack: TrackInfo | null = null;
  private playQueue: TrackInfo[] = [];
  private currentIndex: number = -1;
  private playMode: PlayMode = PlayMode.ORDER;
  // 进度更新定时器
  private progressTimer: number = -1;
  private isInitialized: boolean = false;

  private constructor() {
  }

  /**
   * 获取音频服务实例
   */
  static getInstance(): AudioSvc {
    if (!AudioSvc.instance) {
      AudioSvc.instance = new AudioSvc();
    }
    return AudioSvc.instance;
  }

  /**
   * 初始化音频服务
   * @param context 应用上下文
   */
  async init(context: Context): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      // 创建 AVPlayer
      this.avPlayer = await media.createAVPlayer();
      this.setupPlayerListeners();

      // 创建 AVSession
      this.avSession = await avSession.createAVSession(context, 'MusicPlayer', 'audio');
      this.setupSessionListeners();

      this.isInitialized = true;
      console.info('音频服务初始化成功');
    } catch (err) {
      console.error('音频服务初始化失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 设置播放器事件监听
   */
  private setupPlayerListeners(): void {
    if (!this.avPlayer) {
      return;
    }

    // 状态变化监听
    this.avPlayer.on('stateChange', (state: string) => {
      console.info(`播放器状态变化: ${state}`);

      switch (state) {
        case 'idle':
          this.currentState = PlayerState.IDLE;
          break;
        case 'initialized':
          this.currentState = PlayerState.INITIALIZED;
          // 自动调用 prepare
          console.info('状态 initialized，自动调用 prepare');
          this.avPlayer?.prepare();
          break;
        case 'preparing':
          this.currentState = PlayerState.PREPARING;
          break;
        case 'prepared':
          this.currentState = PlayerState.PREPARED;
          this.onPrepared();
          break;
        case 'playing':
          this.currentState = PlayerState.PLAYING;
          this.startProgressUpdate();
          this.emitPlayStateChanged();
          break;
        case 'paused':
          this.currentState = PlayerState.PAUSED;
          this.stopProgressUpdate();
          this.emitPlayStateChanged();
          break;
        case 'completed':
          this.currentState = PlayerState.COMPLETED;
          this.onCompleted();
          break;
        case 'stopped':
          this.currentState = PlayerState.STOPPED;
          this.stopProgressUpdate();
          break;
        case 'error':
          this.currentState = PlayerState.ERROR;
          this.stopProgressUpdate();
          break;
        case 'released':
          this.currentState = PlayerState.RELEASED;
          break;
      }
    });

    // 错误监听
    this.avPlayer.on('error', (err) => {
      console.error('播放器错误:', err);
      this.currentState = PlayerState.ERROR;
      this.stopProgressUpdate();
    });

    // 播放进度监听（用于精确进度）
    this.avPlayer.on('timeUpdate', (time: number) => {
      this.emitProgressUpdate(time);
    });
  }

  /**
   * 设置 AVSession 监听
   */
  private setupSessionListeners(): void {
    if (!this.avSession) {
      return;
    }

    // 播放控制
    this.avSession.on('play', () => {
      this.play();
    });

    this.avSession.on('pause', () => {
      this.pause();
    });

    this.avSession.on('stop', () => {
      this.stop();
    });

    this.avSession.on('playNext', () => {
      this.next();
    });

    this.avSession.on('playPrevious', () => {
      this.previous();
    });

    this.avSession.on('seek', (time: number) => {
      this.seekTo(time);
    });
  }

  /**
   * 播放器准备完成回调
   */
  private onPrepared(): void {
    // 自动开始播放
    this.avPlayer?.play();

    // 更新 AVSession 元数据
    this.updateSessionMetadata();
  }

  /**
   * 播放完成回调
   */
  private onCompleted(): void {
    // 根据播放模式处理
    switch (this.playMode) {
      case PlayMode.SINGLE_LOOP:
        // 单曲循环，重新播放
        this.seekTo(0);
        this.play();
        break;
      case PlayMode.RANDOM:
      case PlayMode.ORDER:
      default:
      // 播放下一首
        this.next();
        break;
    }
  }

  /**
   * 加载并播放歌曲
   * @param track 歌曲信息
   */
  async loadTrack(track: TrackInfo): Promise<void> {
    if (!this.avPlayer || !this.isInitialized) {
      throw new Error('播放器未初始化');
    }

    try {
      // 停止当前播放
      if (this.currentState === PlayerState.PLAYING ||
        this.currentState === PlayerState.PAUSED) {
        this.avPlayer.stop();
      }

      // 重置播放器
      await this.avPlayer.reset();

      // 使用文件描述符设置数据源（AVPlayer 需要 fd:// 格式）
      console.info(`打开文件: ${track.filePath}`);
      const file = fileIo.openSync(track.filePath, fileIo.OpenMode.READ_ONLY);
      const fileSize = fileIo.statSync(track.filePath).size;
      console.info(`文件大小: ${fileSize}, fd: ${file.fd}`);

      const fdSrc: media.AVFileDescriptor = {
        fd: file.fd,
        offset: 0,
        length: fileSize
      };
      this.avPlayer.fdSrc = fdSrc;

      this.currentTrack = track;

      // 更新当前索引
      const index = this.playQueue.findIndex((t: TrackInfo): boolean => t.id === track.id);
      if (index >= 0) {
        this.currentIndex = index;
      }

      // 触发歌曲变化事件
      this.emitTrackChanged();

      console.info(`加载歌曲成功: ${track.title}, 等待准备完成自动播放`);
    } catch (err) {
      console.error('加载歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 播放
   */
  play(): void {
    if (!this.avPlayer) {
      return;
    }

    try {
      if (this.currentState === PlayerState.PREPARED ||
        this.currentState === PlayerState.PAUSED) {
        this.avPlayer.play();
      } else if (this.currentState === PlayerState.IDLE && this.currentTrack) {
        // 重新加载当前歌曲
        this.loadTrack(this.currentTrack);
      }
    } catch (err) {
      console.error('播放失败:', err);
    }
  }

  /**
   * 暂停
   */
  pause(): void {
    if (!this.avPlayer) {
      return;
    }

    try {
      if (this.currentState === PlayerState.PLAYING) {
        this.avPlayer.pause();
      }
    } catch (err) {
      console.error('暂停失败:', err);
    }
  }

  /**
   * 停止
   */
  stop(): void {
    if (!this.avPlayer) {
      return;
    }

    try {
      this.avPlayer.stop();
      this.stopProgressUpdate();
    } catch (err) {
      console.error('停止失败:', err);
    }
  }

  /**
   * 跳转到指定位置
   * @param position 位置（毫秒）
   */
  seekTo(position: number): void {
    if (!this.avPlayer) {
      return;
    }

    try {
      const duration = this.getDuration();
      if (duration > 0 && position >= 0 && position <= duration) {
        this.avPlayer.seek(position);
      }
    } catch (err) {
      console.error('跳转失败:', err);
    }
  }

  /**
   * 下一首
   */
  next(): void {
    if (this.playQueue.length === 0) {
      return;
    }

    let nextIndex: number;

    switch (this.playMode) {
      case PlayMode.RANDOM:
        // 随机播放
        nextIndex = Math.floor(Math.random() * this.playQueue.length);
        break;
      case PlayMode.ORDER:
      case PlayMode.SINGLE_LOOP:
      default:
      // 顺序播放
        nextIndex = (this.currentIndex + 1) % this.playQueue.length;
        break;
    }

    const nextTrack = this.playQueue[nextIndex];
    if (nextTrack) {
      this.currentIndex = nextIndex;
      this.loadTrack(nextTrack);
    }
  }

  /**
   * 上一首
   */
  previous(): void {
    if (this.playQueue.length === 0) {
      return;
    }

    let prevIndex: number;

    switch (this.playMode) {
      case PlayMode.RANDOM:
        // 随机播放
      // prevIndex = Math.floor(Math.random() * this.playQueue.length);
      // break;
      case PlayMode.ORDER:
      case PlayMode.SINGLE_LOOP:
      default:
      // 顺序播放
        prevIndex = (this.currentIndex - 1 + this.playQueue.length) % this.playQueue.length;
        break;
    }

    const prevTrack = this.playQueue[prevIndex];
    if (prevTrack) {
      this.currentIndex = prevIndex;
      this.loadTrack(prevTrack);
    }
  }

  /**
   * 设置播放列表
   * @param tracks 歌曲列表
   * @param startIndex 开始播放的索引
   */
  setPlayQueue(tracks: TrackInfo[], startIndex: number = 0): void {
    this.playQueue = [...tracks];

    if (startIndex >= 0 && startIndex < tracks.length) {
      this.currentIndex = startIndex;
      this.loadTrack(tracks[startIndex]);
    }
  }

  /**
   * 添加歌曲到播放列表
   * @param track 歌曲
   */
  addToQueue(track: TrackInfo): void {
    if (!this.playQueue.find(t => t.id === track.id)) {
      this.playQueue.push(track);
    }
  }

  /**
   * 清空播放列表
   */
  clearQueue(): void {
    this.playQueue = [];
    this.currentIndex = -1;
  }

  /**
   * 设置播放模式
   * @param mode 播放模式
   */
  setPlayMode(mode: PlayMode): void {
    this.playMode = mode;
  }

  /**
   * 获取播放模式
   */
  getPlayMode(): PlayMode {
    return this.playMode;
  }

  /**
   * 切换播放模式
   */
  togglePlayMode(): PlayMode {
    const modes = [PlayMode.ORDER, PlayMode.RANDOM, PlayMode.SINGLE_LOOP];
    const currentIndex = modes.indexOf(this.playMode);
    const nextIndex = (currentIndex + 1) % modes.length;
    this.playMode = modes[nextIndex];
    return this.playMode;
  }

  /**
   * 获取当前播放状态
   */
  getCurrentState(): PlayerState {
    return this.currentState;
  }

  /**
   * 获取当前播放歌曲
   */
  getCurrentTrack(): TrackInfo | null {
    return this.currentTrack;
  }

  /**
   * 获取播放列表
   */
  getPlayQueue(): TrackInfo[] {
    return [...this.playQueue];
  }

  /**
   * 获取当前播放索引
   */
  getCurrentIndex(): number {
    return this.currentIndex;
  }

  /**
   * 获取当前播放位置（毫秒）
   */
  getCurrentPosition(): number {
    if (!this.avPlayer) {
      return 0;
    }
    // AVPlayer.currentTime 返回的是毫秒
    return this.avPlayer.currentTime;
  }

  /**
   * 获取歌曲总时长（毫秒）
   */
  getDuration(): number {
    if (!this.avPlayer) {
      return 0;
    }
    // AVPlayer.duration 返回的是毫秒
    return this.avPlayer.duration;
  }

  /**
   * 获取播放进度信息
   */
  getProgressInfo(): ProgressInfo {
    const currentTime = this.getCurrentPosition();
    const duration = this.getDuration();
    const progress = duration > 0 ? currentTime / duration : 0;

    return {
      currentTime,
      duration,
      progress
    };
  }

  /**
   * 是否正在播放
   */
  isPlaying(): boolean {
    return this.currentState === PlayerState.PLAYING;
  }

  /**
   * 更新 AVSession 元数据
   */
  private async updateSessionMetadata(): Promise<void> {
    if (!this.avSession || !this.currentTrack) {
      return;
    }

    try {
      const metadata: avSession.AVMetadata = {
        assetId: this.currentTrack.id.toString(),
        title: this.currentTrack.title,
        artist: this.currentTrack.artist,
        album: this.currentTrack.album,
        duration: this.currentTrack.duration,
        mediaImage: this.currentTrack.coverUri || ''
      };

      await this.avSession.setAVMetadata(metadata);

      // 更新播放状态
      const playbackState: avSession.AVPlaybackState = {
        state: this.isPlaying() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
          avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: this.getCurrentPosition(),
          updateTime: Date.now()
        }
      };

      await this.avSession.setAVPlaybackState(playbackState);
    } catch (err) {
      console.error('更新 AVSession 元数据失败:', err);
    }
  }

  /**
   * 开始进度更新
   */
  private startProgressUpdate(): void {
    this.stopProgressUpdate();

    // 使用定时器定期更新进度
    this.progressTimer = setInterval(() => {
      const position = this.getCurrentPosition();
      this.emitProgressUpdate(position);
      this.updateSessionMetadata();
    }, 1000);
  }

  /**
   * 停止进度更新
   */
  private stopProgressUpdate(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  /**
   * 触发歌曲变化事件
   */
  private emitTrackChanged(): void {
    const eventData: emitter.EventData = {
      data: {
        track: this.currentTrack
      }
    };

    emitter.emit({ eventId: 1 }, eventData);
  }

  /**
   * 触发播放状态变化事件
   */
  private emitPlayStateChanged(): void {
    const eventData: emitter.EventData = {
      data: {
        isPlaying: this.isPlaying(),
        state: this.currentState
      }
    };

    emitter.emit({ eventId: 2 }, eventData);
  }

  /**
   * 触发进度更新事件
   */
  private emitProgressUpdate(position: number): void {
    const duration = this.getDuration();
    const eventData: emitter.EventData = {
      data: {
        currentTime: position,
        duration: duration,
        progress: duration > 0 ? position / duration : 0
      }
    };

    emitter.emit({ eventId: 3 }, eventData);
  }

  /**
   * 获取当前播放状态（用于持久化保存）
   */
  getPlaybackStateForSave(): SavedPlaybackState | null {
    if (!this.currentTrack) {
      return null;
    }

    const queueIds: number[] = this.playQueue.map((t: TrackInfo): number => t.id);

    return {
      trackId: this.currentTrack.id,
      trackTitle: this.currentTrack.title,
      trackArtist: this.currentTrack.artist || '',
      trackFile: this.currentTrack.filePath,
      trackDuration: this.currentTrack.duration,
      trackCover: this.currentTrack.coverUri || '',
      trackAlbum: this.currentTrack.album || '',
      position: this.getCurrentPosition(),
      queueIds: JSON.stringify(queueIds),
      queueIndex: this.currentIndex,
      playMode: this.playMode
    };
  }

  /**
   * 恢复播放状态
   * @param state 保存的状态
   * @param tracks 从数据库加载的歌曲列表（用于重建播放队列）
   */
  async restorePlaybackState(state: SavedPlaybackState, tracks: TrackInfo[]): Promise<void> {
    if (tracks.length === 0) {
      return;
    }

    // 恢复播放模式
    this.playMode = state.playMode as PlayMode;

    // 重建播放队列
    this.playQueue = tracks;

    // 找到当前歌曲
    const currentTrack = tracks.find((t: TrackInfo): boolean => t.id === state.trackId);
    if (currentTrack) {
      this.currentIndex = state.queueIndex >= 0 && state.queueIndex < tracks.length ? state.queueIndex : 0;
      await this.loadTrack(currentTrack);
      // 恢复播放进度
      if (state.position > 0) {
        this.seekTo(state.position);
      }
      console.info(`[AudioSvc] 恢复播放状态: ${currentTrack.title}, 进度 ${state.position}ms`);
    }
  }

  /**
   * 释放资源
   */
  async release(): Promise<void> {
    this.stopProgressUpdate();

    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }

    if (this.avSession) {
      await this.avSession.destroy();
      this.avSession = null;
    }

    this.isInitialized = false;
    console.info('音频服务已释放');
  }
}
