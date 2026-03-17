/**
 * 数据库服务类
 * 使用关系型数据库 (RDB) 管理歌曲和歌单数据
 */

import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { TrackInfo } from '../models/TrackInfo';
import { PlayList, PlaylistTrack } from '../models/PlayList';
import { SearchHistory } from '../models/SearchHistory';
import {
  DATABASE_NAME,
  DEFAULT_PLAYLIST_FAVORITE,
  DEFAULT_PLAYLIST_RECENT,
  PLAYLIST_TABLE,
  PLAYLIST_TRACK_TABLE,
  SEARCH_HISTORY_TABLE,
  TRACK_TABLE
} from '../constants/AppConstants';

/**
 * 数据库服务（单例模式）
 */
export class Database {
  private static instance: Database;
  private rdbStore: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;

  private constructor() {
  }

  /**
   * 获取数据库服务实例
   */
  static getInstance(): Database {
    if (!Database.instance) {
      Database.instance = new Database();
    }
    return Database.instance;
  }

  /**
   * 初始化数据库
   * @param context 应用上下文
   */
  async init(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);

      // 设置 WAL 模式提升并发性能
      await this.rdbStore.executeSql('PRAGMA journal_mode=WAL;');

      // 创建表
      await this.createTables();

      // 初始化默认歌单
      await this.initDefaultPlaylists();

      this.initialized = true;
      console.info('数据库初始化成功');
    } catch (err) {
      console.error('数据库初始化失败:', err);
      throw new Error('数据库初始化失败: ' + (err instanceof Error ? err.message : String(err)));
    }
  }

  /**
   * 创建数据库表
   */
  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    let inits: string[] = [];

    // 创建 track 表
    const createTrackTableSQL = `
      CREATE TABLE IF NOT EXISTS ${TRACK_TABLE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        artist TEXT DEFAULT '未知歌手',
        album TEXT DEFAULT '未知专辑',
        duration INTEGER NOT NULL,
        file_path TEXT UNIQUE NOT NULL,
        cover_uri TEXT,
        added_at INTEGER NOT NULL
      )
    `;
    inits.push(createTrackTableSQL);

    // 创建 playlist 表
    const createPlaylistTableSQL = `
      CREATE TABLE IF NOT EXISTS ${PLAYLIST_TABLE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        create_at INTEGER NOT NULL
      )
    `;
    inits.push(createPlaylistTableSQL)

    // 创建 playlist_track 关联表
    const createPlaylistTrackTableSQL = `
      CREATE TABLE IF NOT EXISTS ${PLAYLIST_TRACK_TABLE} (
        playlist_id INTEGER,
        track_id INTEGER,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id),
        FOREIGN KEY (playlist_id) REFERENCES ${PLAYLIST_TABLE}(id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES ${TRACK_TABLE}(id) ON DELETE CASCADE
      )
    `;
    inits.push(createPlaylistTrackTableSQL);

    const createSearchHistoryTableSQL = `
      CREATE TABLE IF NOT EXISTS ${SEARCH_HISTORY_TABLE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL
      )
    `;
    inits.push(createSearchHistoryTableSQL);

    for (const sql of inits) {
      try {
        await this.rdbStore.executeSql(sql);
        console.info('数据库表创建成功');
      } catch (err) {
        console.error('创建数据库表失败:', err);
        throw new Error(err instanceof Error ? err.message : String(err));
      }
    }
  }

  /**
   * 初始化默认歌单
   */
  private async initDefaultPlaylists(): Promise<void> {
    // 检查是否已存在默认歌单
    const playlists = await this.getAllPlaylists();

    if (!playlists.find(p => p.name === DEFAULT_PLAYLIST_FAVORITE)) {
      await this.createPlaylist(DEFAULT_PLAYLIST_FAVORITE);
    }

    if (!playlists.find(p => p.name === DEFAULT_PLAYLIST_RECENT)) {
      await this.createPlaylist(DEFAULT_PLAYLIST_RECENT);
    }
  }

  // ==================== Track 操作 ====================

  /**
   * 插入单首歌曲
   * @param track 歌曲信息
   * @returns 插入后的歌曲 ID
   */
  async insertTrack(track: TrackInfo): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const id = await this.rdbStore.insert(TRACK_TABLE, track.toValuesBucket());
      console.info(`歌曲插入成功: ${track.title}, ID: ${id}`);
      return id;
    } catch (err) {
      // 处理唯一约束冲突
      if ((err as BusinessError).code === 14800011) {
        console.warn(`歌曲已存在: ${track.filePath}`);
        return -1;
      }
      console.error('插入歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 批量插入歌曲（事务）
   * @param tracks 歌曲列表
   * @returns 成功插入的数量
   */
  async batchInsertTracks(tracks: TrackInfo[]): Promise<number> {
    if (!this.rdbStore || tracks.length === 0) {
      return 0;
    }

    let successCount = 0;

    // 批量插入，每条记录单独处理
    for (const track of tracks) {
      try {
        await this.rdbStore.insert(TRACK_TABLE, track.toValuesBucket());
        successCount++;
      } catch (err) {
        // 忽略重复项
        if ((err as BusinessError).code !== 14800011) {
          console.error('批量插入歌曲失败:', err);
        }
      }
    }

    console.info(`批量插入完成: ${successCount}/${tracks.length}`);
    return successCount;
  }

  /**
   * 获取所有歌曲
   * @returns 歌曲列表
   */
  async getAllTracks(): Promise<TrackInfo[]> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const tracks: TrackInfo[] = [];

    try {
      const predicates = new relationalStore.RdbPredicates(TRACK_TABLE);
      predicates.orderByDesc('added_at');

      const resultSet = await this.rdbStore.query(predicates);

      while (resultSet.goToNextRow()) {
        tracks.push(TrackInfo.fromResultSet(resultSet));
      }

      resultSet.close();
      return tracks;
    } catch (err) {
      console.error('获取所有歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 根据 ID 获取歌曲
   * @param id 歌曲 ID
   * @returns 歌曲信息
   */
  async getTrackById(id: number): Promise<TrackInfo | null> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(TRACK_TABLE);
      predicates.equalTo('id', id);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const track = TrackInfo.fromResultSet(resultSet);
        resultSet.close();
        return track;
      }

      resultSet.close();
      return null;
    } catch (err) {
      console.error('获取歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 根据文件路径获取歌曲
   * @param filePath 文件路径
   * @returns 歌曲信息
   */
  async getTrackByPath(filePath: string): Promise<TrackInfo | null> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(TRACK_TABLE);
      predicates.equalTo('file_path', filePath);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const track = TrackInfo.fromResultSet(resultSet);
        resultSet.close();
        return track;
      }

      resultSet.close();
      return null;
    } catch (err) {
      console.error('获取歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 删除歌曲
   * @param id 歌曲 ID
   */
  async deleteTrack(id: number): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(TRACK_TABLE);
      predicates.equalTo('id', id);

      const deleteRows = await this.rdbStore.delete(predicates);
      console.info(`删除歌曲成功: ${id}, 影响行数: ${deleteRows}`);
    } catch (err) {
      console.error('删除歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 搜索歌曲
   * @param keyword 搜索关键词
   * @returns 匹配的歌曲列表
   */
  async searchTracks(keyword: string): Promise<TrackInfo[]> {
    if (!this.rdbStore || !keyword.trim()) {
      return [];
    }

    const tracks: TrackInfo[] = [];
    const searchPattern = `%${keyword.trim()}%`;

    try {
      const sql = `
        SELECT * FROM ${TRACK_TABLE} 
        WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?
        ORDER BY added_at DESC
      `;

      const resultSet = await this.rdbStore.querySql(sql, [searchPattern, searchPattern, searchPattern]);

      while (resultSet.goToNextRow()) {
        tracks.push(TrackInfo.fromResultSet(resultSet));
      }

      resultSet.close();
      return tracks;
    } catch (err) {
      console.error('搜索歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  // ==================== Playlist 操作 ====================

  /**
   * 创建歌单
   * @param name 歌单名称
   * @returns 歌单 ID
   */
  async createPlaylist(name: string): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const playlist = new PlayList({
      name: name,
      createAt: Date.now()
    });

    try {
      const id = await this.rdbStore.insert(PLAYLIST_TABLE, playlist.toValuesBucket());
      console.info(`歌单创建成功: ${name}, ID: ${id}`);
      return id;
    } catch (err) {
      console.error('创建歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 获取所有歌单
   * @returns 歌单列表
   */
  async getAllPlaylists(): Promise<PlayList[]> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const playlists: PlayList[] = [];

    try {
      const predicates = new relationalStore.RdbPredicates(PLAYLIST_TABLE);
      predicates.orderByDesc('create_at');

      const resultSet = await this.rdbStore.query(predicates);

      while (resultSet.goToNextRow()) {
        playlists.push(PlayList.fromResultSet(resultSet));
      }

      resultSet.close();
      return playlists;
    } catch (err) {
      console.error('获取所有歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 根据 ID 获取歌单
   * @param id 歌单 ID
   * @returns 歌单信息
   */
  async getPlaylistById(id: number): Promise<PlayList | null> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(PLAYLIST_TABLE);
      predicates.equalTo('id', id);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const playlist = PlayList.fromResultSet(resultSet);
        resultSet.close();

        // 加载歌单中的歌曲
        playlist.tracks = await this.getPlaylistTracks(id);
        return playlist;
      }

      resultSet.close();
      return null;
    } catch (err) {
      console.error('获取歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 根据名称获取歌单
   * @param name 歌单名称
   * @returns 歌单信息
   */
  async getPlaylistByName(name: string): Promise<PlayList | null> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(PLAYLIST_TABLE);
      predicates.equalTo('name', name);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const playlist = PlayList.fromResultSet(resultSet);
        resultSet.close();

        // 加载歌单中的歌曲
        playlist.tracks = await this.getPlaylistTracks(playlist.id);
        return playlist;
      }

      resultSet.close();
      return null;
    } catch (err) {
      console.error('获取歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 删除歌单
   * @param id 歌单 ID
   */
  async deletePlaylist(id: number): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(PLAYLIST_TABLE);
      predicates.equalTo('id', id);

      const deleteRows = await this.rdbStore.delete(predicates);
      console.info(`删除歌单成功: ${id}, 影响行数: ${deleteRows}`);
    } catch (err) {
      console.error('删除歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  // ==================== Playlist-Track 关联操作 ====================

  /**
   * 添加歌曲到歌单
   * @param playlistId 歌单 ID
   * @param trackId 歌曲 ID
   * @returns 是否成功
   */
  async addTrackToPlaylist(playlistId: number, trackId: number): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      // 获取当前最大排序值
      const sql = `SELECT MAX(sort_order) as max_order FROM ${PLAYLIST_TRACK_TABLE} WHERE playlist_id = ?`;
      const resultSet = await this.rdbStore.querySql(sql, [playlistId.toString()]);

      let sortOrder = 0;
      if (resultSet.goToFirstRow()) {
        sortOrder = (resultSet.getLong(resultSet.getColumnIndex('max_order')) || 0) + 1;
      }
      resultSet.close();

      const relation = new PlaylistTrack({
        playlistId: playlistId,
        trackId: trackId,
        sortOrder: sortOrder
      });

      await this.rdbStore.insert(PLAYLIST_TRACK_TABLE, relation.toValuesBucket());
      console.info(`添加歌曲到歌单成功: playlist=${playlistId}, track=${trackId}`);
      return true;
    } catch (err) {
      // 处理重复添加
      if ((err as BusinessError).code === 14800011) {
        console.warn(`歌曲已在歌单中: playlist=${playlistId}, track=${trackId}`);
        return false;
      }
      console.error('添加歌曲到歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 从歌单移除歌曲
   * @param playlistId 歌单 ID
   * @param trackId 歌曲 ID
   */
  async removeTrackFromPlaylist(playlistId: number, trackId: number): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const sql = `DELETE FROM ${PLAYLIST_TRACK_TABLE} WHERE playlist_id = ? AND track_id = ?`;
      await this.rdbStore.executeSql(sql, [playlistId.toString(), trackId.toString()]);
      console.info(`从歌单移除歌曲成功: playlist=${playlistId}, track=${trackId}`);
    } catch (err) {
      console.error('从歌单移除歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 获取歌单中的所有歌曲
   * @param playlistId 歌单 ID
   * @returns 歌曲列表
   */
  async getPlaylistTracks(playlistId: number): Promise<TrackInfo[]> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const tracks: TrackInfo[] = [];

    try {
      const sql = `
        SELECT t.* FROM ${TRACK_TABLE} t
        INNER JOIN ${PLAYLIST_TRACK_TABLE} pt ON t.id = pt.track_id
        WHERE pt.playlist_id = ?
        ORDER BY pt.sort_order ASC
      `;

      const resultSet = await this.rdbStore.querySql(sql, [playlistId.toString()]);

      while (resultSet.goToNextRow()) {
        tracks.push(TrackInfo.fromResultSet(resultSet));
      }

      resultSet.close();
      return tracks;
    } catch (err) {
      console.error('获取歌单歌曲失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 获取歌曲所在的歌单
   * @param trackId 歌曲 ID
   * @returns 歌单 ID 列表
   */
  async getTrackPlaylists(trackId: number): Promise<number[]> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const playlistIds: number[] = [];

    try {
      const predicates = new relationalStore.RdbPredicates(PLAYLIST_TRACK_TABLE);
      predicates.equalTo('track_id', trackId);

      const resultSet = await this.rdbStore.query(predicates);

      while (resultSet.goToNextRow()) {
        playlistIds.push(resultSet.getLong(resultSet.getColumnIndex('playlist_id')));
      }

      resultSet.close();
      return playlistIds;
    } catch (err) {
      console.error('获取歌曲所在歌单失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 获取歌曲总数
   * @returns 歌曲数量
   */
  async getTrackCount(): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const sql = `SELECT COUNT(*) as count FROM ${TRACK_TABLE}`;
      const resultSet = await this.rdbStore.querySql(sql);

      let count = 0;
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('count'));
      }

      resultSet.close();
      return count;
    } catch (err) {
      console.error('获取歌曲数量失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  // ==================== SearchHistory 操作 ====================

  /**
   * 添加搜索历史记录
   * @param keyword 搜索关键词
   * @returns 是否成功
   */
  async addSearchHistoryRecord(keyword: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    if (!keyword.trim()) {
      return false;
    }

    const trimmedKeyword = keyword.trim();

    try {
      // 先检查是否已存在相同关键词
      const existingRecord = await this.getSearchHistoryRecord(trimmedKeyword);

      if (existingRecord) {
        // 如果已存在，更新其时间戳
        const predicates = new relationalStore.RdbPredicates(SEARCH_HISTORY_TABLE);
        predicates.equalTo('keyword', trimmedKeyword);

        const valuesBucket: relationalStore.ValuesBucket = {
          timestamp: Date.now()
        };

        await this.rdbStore.update(valuesBucket, predicates);
        console.info(`搜索历史记录已更新: ${trimmedKeyword}`);
      } else {
        // 如果不存在，插入新记录
        const valuesBucket: relationalStore.ValuesBucket = {
          keyword: trimmedKeyword,
          timestamp: Date.now()
        };

        await this.rdbStore.insert(SEARCH_HISTORY_TABLE, valuesBucket);
        console.info(`搜索历史记录已添加: ${trimmedKeyword}`);
      }

      return true;
    } catch (err) {
      console.error('添加搜索历史记录失败:', err);
      return false;
    }
  }

  /**
   * 获取搜索历史记录
   * @param limit 限制返回数量，默认10条
   * @returns 搜索历史关键词列表
   */
  async getSearchHistory(limit: number = 10): Promise<string[]> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    const keywords: string[] = [];

    try {
      const predicates = new relationalStore.RdbPredicates(SEARCH_HISTORY_TABLE);
      predicates.orderByDesc('timestamp');

      const resultSet = await this.rdbStore.query(predicates);

      let count = 0;
      while (resultSet.goToNextRow() && count < limit) {
        const keyword = resultSet.getString(resultSet.getColumnIndex('keyword'));
        keywords.push(keyword);
        count++;
      }

      resultSet.close();
      return keywords;
    } catch (err) {
      console.error('获取搜索历史失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 获取特定搜索历史记录
   * @param keyword 搜索关键词
   * @returns 搜索历史记录信息
   */
  async getSearchHistoryRecord(keyword: string): Promise<SearchHistory | null> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SEARCH_HISTORY_TABLE);
      predicates.equalTo('keyword', keyword);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const searchHistory = new SearchHistory({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          keyword: resultSet.getString(resultSet.getColumnIndex('keyword')),
          timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp'))
        });

        resultSet.close();
        return searchHistory;
      }

      resultSet.close();
      return null;
    } catch (err) {
      console.error('获取搜索历史记录失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  /**
   * 删除特定搜索历史记录
   * @param keyword 搜索关键词
   * @returns 是否成功
   */
  async deleteSearchHistoryRecord(keyword: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SEARCH_HISTORY_TABLE);
      predicates.equalTo('keyword', keyword);

      const deleteRows = await this.rdbStore.delete(predicates);
      console.info(`删除搜索历史记录成功: ${keyword}, 影响行数: ${deleteRows}`);
      return deleteRows > 0;
    } catch (err) {
      console.error('删除搜索历史记录失败:', err);
      return false;
    }
  }

  /**
   * 清空所有搜索历史记录
   * @returns 是否成功
   */
  async clearSearchHistory(): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SEARCH_HISTORY_TABLE);
      const deleteRows = await this.rdbStore.delete(predicates);
      console.info(`清空搜索历史记录成功, 影响行数: ${deleteRows}`);
      return true;
    } catch (err) {
      console.error('清空搜索历史记录失败:', err);
      return false;
    }
  }

  /**
   * 获取搜索历史记录数量
   * @returns 记录数量
   */
  async getSearchHistoryCount(): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化');
    }

    try {
      const sql = `SELECT COUNT(*) as count FROM ${SEARCH_HISTORY_TABLE}`;
      const resultSet = await this.rdbStore.querySql(sql);

      let count = 0;
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('count'));
      }

      resultSet.close();
      return count;
    } catch (err) {
      console.error('获取搜索历史数量失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }


  /**
   * 关闭数据库
   */
  async close(): Promise<void> {
    if (this.rdbStore) {
      await this.rdbStore.close();
      this.rdbStore = null;
      this.initialized = false;
      console.info('数据库已关闭');
    }
  }
}
