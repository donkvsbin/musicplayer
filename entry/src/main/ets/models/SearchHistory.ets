import { relationalStore } from '@kit.ArkData';

/**
 * 搜索历史数据模型
 */
export interface SearchHistoryOptions {
  id?: number;
  keyword?: string;
  timestamp?: number;
}

export class SearchHistory {
  id: number = 0;
  keyword: string = '';
  timestamp: number = 0;

  constructor(options?: SearchHistoryOptions) {
    if (options) {
      this.id = options.id ?? 0;
      this.keyword = options.keyword ?? '';
      this.timestamp = options.timestamp ?? Date.now();
    }
  }

  /**
   * 转换为数据库插入值
   */
  toValuesBucket(): relationalStore.ValuesBucket {
    return {
      keyword: this.keyword,
      timestamp: this.timestamp
    };
  }

  /**
   * 从查询结果集创建对象
   */
  static fromResultSet(resultSet: relationalStore.ResultSet): SearchHistory {
    return new SearchHistory({
      id: resultSet.getLong(resultSet.getColumnIndex('id')),
      keyword: resultSet.getString(resultSet.getColumnIndex('keyword')),
      timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp'))
    });
  }

  /**
   * 获取示例数据（用于测试）
   */
  static getSampleData(): SearchHistory[] {
    return [
      new SearchHistory({ keyword: '周杰伦', timestamp: Date.now() - 3600000 }),
      new SearchHistory({ keyword: '流行音乐', timestamp: Date.now() - 7200000 }),
      new SearchHistory({ keyword: '摇滚', timestamp: Date.now() - 10800000 })
    ];
  }
}