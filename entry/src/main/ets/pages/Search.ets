/**
 * 搜索页面
 * 支持实时前缀搜索、模糊搜索及防抖优化
 */

import { router } from '@kit.ArkUI';
import { TrackInfo } from '../models/TrackInfo';
import { Database } from '../services/Database';
import { AudioSvc } from '../services/AudioSvc';
import { SearchManager } from '../utils/TrieTree';
import { TrackItem } from '../views/TrackItem';
import { SearchHistory } from '../models/SearchHistory';
import { MiniPlayer } from '../views/MiniPlayer';

@Entry
@Component
struct SearchPage {
  @State private searchKeyword: string = '';
  @State private searchResults: TrackInfo[] = [];
  @State private allTracks: TrackInfo[] = [];
  @State private searchHistory: string[] = [];
  @State private isSearching: boolean = false;
  @State private hasSearched: boolean = false;
  // 增加防抖定时器
  private searchTimeout: number = -1;

  private database: Database = Database.getInstance();
  private audioSvc: AudioSvc = AudioSvc.getInstance();
  private searchManager: SearchManager = new SearchManager();

  aboutToAppear() {
    this.loadAllTracks();
    this.loadSearchHistory();
  }

  private async loadAllTracks() {
    try {
      this.allTracks = await this.database.getAllTracks();
      this.searchManager.initialize(this.allTracks);
    } catch (err) {
      console.error('加载歌曲失败:', err);
    }
  }

  private async loadSearchHistory() {
    try {
      this.searchHistory = await this.database.getSearchHistory();
    } catch (err) {
      console.error('加载搜索历史记录失败:', err);
      this.searchHistory = SearchHistory.getSampleData().map(history => history.keyword);
    }
  }

  private async saveSearchHistory(keyword: string) {
    if (!keyword.trim()) return;

    try {
      await this.database.addSearchHistoryRecord(keyword);
      await this.loadSearchHistory();
    } catch (err) {
      console.error('保存搜索历史记录失败:', err);
      const trimmedKeyword = keyword.trim();
      const index = this.searchHistory.indexOf(trimmedKeyword);
      if (index > -1) {
        this.searchHistory.splice(index, 1);
      }
      this.searchHistory.unshift(trimmedKeyword);
      if (this.searchHistory.length > 10) {
        this.searchHistory = this.searchHistory.slice(0, 10);
      }
    }
  }

  private onSearchInputChange(keyword: string) {
    this.searchKeyword = keyword;

    if (keyword.trim().length === 0) {
      this.clearSearch();
      return;
    }

    // UX优化：防抖处理，避免用户快速打字时频繁触发搜索
    if (this.searchTimeout !== -1) {
      clearTimeout(this.searchTimeout);
    }

    this.isSearching = true;
    this.hasSearched = true;

    this.searchTimeout = setTimeout(() => {
      this.performSearch(keyword);
    }, 300) as number;
  }

  private performSearch(keyword: string) {
    let results = this.searchManager.search(keyword);

    if (results.length < 5) {
      const fuzzyResults = this.searchManager.fuzzySearch(keyword);
      const resultIds = new Set(results.map(t => t.id));
      for (const track of fuzzyResults) {
        if (!resultIds.has(track.id)) {
          results.push(track);
        }
      }
    }

    this.searchResults = results;
    this.isSearching = false;
  }

  private onSearchSubmit() {
    if (this.searchKeyword.trim()) {
      // 如果定时器还在运行，清理掉并立即执行搜索
      if (this.searchTimeout !== -1) {
        clearTimeout(this.searchTimeout);
      }
      this.saveSearchHistory(this.searchKeyword);
      this.performSearch(this.searchKeyword);
    }
  }

  private clearSearch() {
    this.searchKeyword = '';
    this.searchResults = [];
    this.hasSearched = false;
    this.isSearching = false;
  }

  private async clearHistory() {
    try {
      await this.database.clearSearchHistory();
      this.searchHistory = [];
    } catch (err) {
      console.error('清空搜索历史记录失败:', err);
      this.searchHistory = [];
    }
  }

  private playTrack(track: TrackInfo) {
    const playlistName = this.searchKeyword ? `搜索: ${this.searchKeyword}` : '搜索结果';
    this.audioSvc.setPlayQueue(this.searchResults.length > 0 ? this.searchResults : [track], 0, playlistName);
    this.audioSvc.loadTrack(track);
  }

  private async navigateBack() {
    try {
      await router.back();
    } catch (err) {
      console.error('返回失败:', err);
    }
  }

  build() {
    Column() {
      // 顶部搜索栏
      Row() {
        Button() {
          Image($r('app.media.icon_back'))
            .width(24)
            .height(24)
            .fillColor('#333333')
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .width(44)
        .height(44)
        .onClick(() => this.navigateBack())

        // 搜索输入框
        Row() {
          Image($r('app.media.icon_music_note'))
            .width(18)
            .height(18)
            .fillColor('#999999')
            .margin({ left: 12, right: 8 })

          TextInput({ placeholder: '搜索歌曲、歌手、专辑', text: this.searchKeyword })
            .placeholderColor('#BDBDBD')
            .fontSize(14)
            .height(40)
            .backgroundColor('transparent')
            .layoutWeight(1)
            .enterKeyType(EnterKeyType.Search) // UX优化：软键盘显示“搜索”按钮
            .defaultFocus(true) // UX优化：进入页面自动拉起键盘
            .onChange((value: string) => {
              this.onSearchInputChange(value);
            })
            .onSubmit(() => {
              this.onSearchSubmit();
            })

          if (this.searchKeyword.length > 0) {
            Button() {
              Image($r('app.media.icon_back'))
                .width(16)
                .height(16)
                .fillColor('#999999')
                .rotate({ angle: 180 })
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(32)
            .height(32)
            .margin({ right: 4 })
            .onClick(() => this.clearSearch())
          }
        }
        .height(40)
        .layoutWeight(1)
        .backgroundColor('#F0F0F0')
        .borderRadius(20)
        .margin({ left: 4, right: 8 })

        // 搜索按钮
        Text('搜索')
          .fontSize(15)
          .fontColor('#FF4081')
          .fontWeight(FontWeight.Medium)
          .padding({ left: 8, right: 8 })
          .onClick(() => this.onSearchSubmit())
      }
      .width('100%')
      .height(80)
      .padding({ left: 8, right: 16, top:40 })
      .backgroundColor('#FFFFFF')

      // 核心内容区域
      if (this.hasSearched) {
        if (this.isSearching) {
          // UX优化：加载中状态指示
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color('#FF4081')
              .margin({ bottom: 12 })
            Text('正在搜索...')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.searchResults.length > 0) {
          // 搜索结果
          List({ space: 0 }) {
            ListItem() {
              Text(`找到 ${this.searchResults.length} 首单曲`)
                .fontSize(13)
                .fontColor('#999999')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })
            }

            ForEach(this.searchResults, (track: TrackInfo, index: number) => {
              ListItem() {
                TrackItem({
                  track: track,
                  index: index + 1,
                  isPlaying: this.audioSvc.getCurrentTrack()?.id === track.id && this.audioSvc.isPlaying(),
                  onTrackClick: (t: TrackInfo): void => { this.playTrack(t); }
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .divider({
            strokeWidth: 0.5,
            color: '#F0F0F0',
            startMargin: 16,
            endMargin: 16
          })
        } else {
          // 空状态优化
          Column() {
            Image($r('app.media.icon_music_note'))
              .width(100)
              .height(100)
              .opacity(0.3)
              .margin({ bottom: 16 })

            Text('未找到相关歌曲')
              .fontSize(16)
              .fontColor('#666666')
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 8 })

            Text('请检查拼写或尝试其他关键词')
              .fontSize(13)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      } else {
        // 搜索历史和推荐区
        Scroll() {
          Column({ space: 20 }) {
            // 搜索历史
            if (this.searchHistory.length > 0) {
              Column({ space: 12 }) {
                Row() {
                  Text('搜索历史')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')

                  Blank() // 自动推开两边

                  Image($r('app.media.icon_playlist'))
                    .width(18)
                    .height(18)
                    .fillColor('#999999')
                    .onClick(() => this.clearHistory())
                }
                .width('100%')
                .padding({ left: 4, right: 4 })

                Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                  ForEach(this.searchHistory, (keyword: string) => {
                    Text(keyword)
                      .fontSize(13)
                      .fontColor('#555555')
                      .backgroundColor('#F5F5F5')
                      .padding({
                        left: 14,
                        right: 14,
                        top: 6,
                        bottom: 6
                      })
                      .borderRadius(16)
                      .margin({ right: 10, bottom: 10 })
                      .onClick(() => {
                        this.searchKeyword = keyword;
                        this.onSearchSubmit();
                      })
                  })
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 20 })
            }

            // 热门搜索
            Column({ space: 12 }) {
              Text('热门搜索')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .width('100%')
                .padding({ left: 4 })

              Column({ space: 0 }) {
                ForEach(['周杰伦', '林俊杰', '薛之谦', '邓紫棋', '陈奕迅', 'Taylor Swift'], (keyword: string, index: number) => {
                  Row() {
                    Text((index + 1).toString())
                      .fontSize(15)
                      .fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(index < 3 ? '#FF4081' : '#BDBDBD')
                      .width(28)

                    Text(keyword)
                      .fontSize(14)
                      .fontColor('#333333')
                      .layoutWeight(1)

                    if (index < 3) {
                      Text('HOT')
                        .fontSize(9)
                        .fontColor('#FF4081')
                        .fontStyle(FontStyle.Italic)
                        .fontWeight(FontWeight.Bold)
                    }
                  }
                  .width('100%')
                  .height(44)
                  .onClick(() => {
                    this.searchKeyword = keyword;
                    this.onSearchSubmit();
                  })
                })
              }
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .padding(12)
              // 轻微阴影提升卡片质感
              .shadow({ radius: 10, color: 'rgba(0,0,0,0.03)', offsetY: 2 })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ bottom: 200 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // 底部留白给迷你播放器
        .padding({ bottom: 64 })
      }

      // 迷你播放条（固定在底部最上层）
      Column() {
        MiniPlayer({
          onExpand: (): void => { 
            router.pushUrl({ url: 'pages/Player' });
          }
        })
      }
      .width('100%')
      .position({ bottom: 0 })
      .zIndex(100)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}