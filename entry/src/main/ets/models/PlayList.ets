/**
 * 歌单实体类
 * 对应数据库 playlist 表
 */

import { relationalStore } from '@kit.ArkData';
import { TrackInfo } from './TrackInfo';

/**
 * PlayList 构造选项接口
 */
export interface PlayListOptions {
  id?: number;
  name?: string;
  createAt?: number;
  tracks?: TrackInfo[];
}

export class PlayList {
  // 歌单 ID
  id: number = -1;
  // 歌单名称
  name: string = '';
  // 创建时间
  createAt: number = Date.now();
  // 歌单中的歌曲列表 (非数据库字段，用于内存缓存)
  tracks: TrackInfo[] = [];

  constructor(options?: PlayListOptions) {
    if (options) {
      this.id = options.id ?? -1;
      this.name = options.name ?? '';
      this.createAt = options.createAt ?? Date.now();
      this.tracks = options.tracks ?? [];
    }
  }

  /**
   * 从 RDB 结果集转换为 PlayList 对象
   */
  static fromResultSet(resultSet: relationalStore.ResultSet): PlayList {
    const playList = new PlayList();
    playList.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    playList.name = resultSet.getString(resultSet.getColumnIndex('name'));
    playList.createAt = resultSet.getLong(resultSet.getColumnIndex('create_at'));
    return playList;
  }

  /**
   * 转换为 RDB 插入/更新数据
   */
  toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'name': this.name,
      'create_at': this.createAt
    };

    if (this.id > 0) {
      bucket['id'] = this.id;
    }

    return bucket;
  }

  /**
   * 获取歌曲数量
   */
  get trackCount(): number {
    return this.tracks.length;
  }

  /**
   * 获取总时长 (毫秒)
   */
  get totalDuration(): number {
    return this.tracks.reduce((sum, track) => sum + track.duration, 0);
  }

  /**
   * 添加歌曲到歌单
   */
  addTrack(track: TrackInfo): void {
    if (!this.tracks.find(t => t.id === track.id)) {
      this.tracks.push(track);
    }
  }

  /**
   * 从歌单移除歌曲
   */
  removeTrack(trackId: number): void {
    const index = this.tracks.findIndex(t => t.id === trackId);
    if (index > -1) {
      this.tracks.splice(index, 1);
    }
  }

  /**
   * 检查歌曲是否在歌单中
   */
  hasTrack(trackId: number): boolean {
    return this.tracks.some(t => t.id === trackId);
  }

  /**
   * 重新排序歌曲
   */
  reorderTracks(newOrder: number[]): void {
    if (newOrder.length !== this.tracks.length) {
      return;
    }
    const reordered: TrackInfo[] = [];
    for (const index of newOrder) {
      if (index >= 0 && index < this.tracks.length) {
        reordered.push(this.tracks[index]);
      }
    }
    this.tracks = reordered;
  }
}

/**
 * PlaylistTrack 构造选项接口
 */
export interface PlaylistTrackOptions {
  playlistId?: number;
  trackId?: number;
  sortOrder?: number;
}

/**
 * 歌单-歌曲关联类
 * 对应数据库 playlist_track 表
 */
export class PlaylistTrack {
  playlistId: number = -1;
  trackId: number = -1;
  sortOrder: number = 0;

  constructor(options?: PlaylistTrackOptions) {
    if (options) {
      this.playlistId = options.playlistId ?? -1;
      this.trackId = options.trackId ?? -1;
      this.sortOrder = options.sortOrder ?? 0;
    }
  }

  static fromResultSet(resultSet: relationalStore.ResultSet): PlaylistTrack {
    const playlistTrack = new PlaylistTrack();
    playlistTrack.playlistId = resultSet.getLong(resultSet.getColumnIndex('playlist_id'));
    playlistTrack.trackId = resultSet.getLong(resultSet.getColumnIndex('track_id'));
    playlistTrack.sortOrder = resultSet.getLong(resultSet.getColumnIndex('sort_order'));
    return playlistTrack;
  }

  toValuesBucket(): relationalStore.ValuesBucket {
    return {
      'playlist_id': this.playlistId,
      'track_id': this.trackId,
      'sort_order': this.sortOrder
    };
  }
}
