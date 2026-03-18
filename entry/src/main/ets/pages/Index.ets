/**
 * 首页 - 音乐播放器主界面
 */

import { router } from '@kit.ArkUI';
import { worker, MessageEvents } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { TrackInfo } from '../models/TrackInfo';
import { PlayList } from '../models/PlayList';
import { Database } from '../services/Database';
import { AudioSvc } from '../services/AudioSvc';
import { MiniPlayer } from '../views/MiniPlayer';
import { DEFAULT_PLAYLIST_FAVORITE, DEFAULT_PLAYLIST_RECENT, AUDIO_EXTENSIONS } from '../constants/AppConstants';
import { PlaybackStateStore } from '../utils/PlaybackStateStore';

interface MenuItem {
  icon: Resource;
  title: string;
  subtitle?: string;
  count?: number;
  onClick: () => void;
}

@Entry
@Component
struct Index {
  @State private trackCount: number = 0;
  @State private recentTracks: TrackInfo[] = [];
  @State private favoritePlaylist: PlayList | null = null;
  @State private isScanning: boolean = false;
  @State private scanProgress: number = 0;
  @State private scanMessage: string = '';
  
  private database: Database = Database.getInstance();
  private audioSvc: AudioSvc = AudioSvc.getInstance();
  private scannerWorker: worker.ThreadWorker | null = null;
  private appContext: Context | null = null;

  aboutToAppear() {
    // 初始化数据库和音频服务
    this.initServices();
  }

  aboutToDisappear() {
    // 释放 Worker
    if (this.scannerWorker) {
      try {
        this.scannerWorker.terminate();
      } catch (err) {
        console.error('终止 Worker 失败:', err);
      }
      this.scannerWorker = null;
    }
  }

  private async initServices() {
    try {
      const context = getContext(this);
      this.appContext = context;
      
      // 复制 rawfile 中的音乐到沙箱目录
      await this.copyRawMusicFiles(context);
      
      // 初始化数据库
      await this.database.init(context);
      
      // 初始化音频服务
      await this.audioSvc.init(context);
      
      // 加载数据
      await this.loadData();
      
      // 恢复上次播放状态
      await this.restorePlaybackState(context);
    } catch (err) {
      console.error('初始化服务失败:', err);
    }
  }

  // 复制 rawfile 中的音乐文件到沙箱目录
  private async copyRawMusicFiles(context: Context) {
    try {
      const resourceManager = context.resourceManager;
      const filesDir = context.filesDir;
      
      // 创建 music 目录
      const musicDir = filesDir + '/music';
      try {
        fileIo.mkdirSync(musicDir);
      } catch (e) {
        // 目录可能已存在，忽略错误
      }
      
      // 获取 rawfile 列表
      const rawFiles = await resourceManager.getRawFileList('');
      console.info('rawfile 文件列表:', JSON.stringify(rawFiles));
      
      for (const fileName of rawFiles) {
        // 检查是否是音频文件
        const lowerName = fileName.toLowerCase();
        const isAudio = AUDIO_EXTENSIONS.some((ext: string): boolean => lowerName.endsWith(ext));
        
        if (isAudio) {
          const targetPath = musicDir + '/' + fileName;
          
          // 检查文件是否已存在
          try {
            fileIo.statSync(targetPath);
            console.info('文件已存在，跳过:', targetPath);
            continue;
          } catch (e) {
            // 文件不存在，继续复制
          }
          
          // 读取 rawfile 内容
          const rawContent = await resourceManager.getRawFileContent(fileName);
          
          // 写入到沙箱目录
          const file = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          fileIo.writeSync(file.fd, rawContent.buffer);
          fileIo.closeSync(file);
          
          console.info('已复制音乐文件:', targetPath);
        }
      }
    } catch (err) {
      console.error('复制 rawfile 音乐失败:', err);
    }
  }

  private async loadData() {
    try {
      // 获取歌曲总数
      this.trackCount = await this.database.getTrackCount();
      
      // 获取最近播放歌单
      this.favoritePlaylist = await this.database.getPlaylistByName(DEFAULT_PLAYLIST_FAVORITE);
      
      // 获取所有歌曲作为最近播放（实际应该按播放时间排序）
      const allTracks = await this.database.getAllTracks();
      this.recentTracks = allTracks.slice(0, 10);
    } catch (err) {
      console.error('加载数据失败:', err);
    }
  }

  /**
   * 恢复上次播放状态
   */
  private async restorePlaybackState(context: Context) {
    try {
      const savedState = await PlaybackStateStore.load(context);
      if (!savedState) {
        return;
      }

      // 获取所有歌曲用于重建播放队列
      const allTracks = await this.database.getAllTracks();
      if (allTracks.length === 0) {
        return;
      }

      // 恢复播放状态
      await this.audioSvc.restorePlaybackState(savedState, allTracks);
      console.info(`[Index] 恢复播放状态成功: ${savedState.trackTitle}`);
    } catch (err) {
      console.error('恢复播放状态失败');
    }
  }

  private startScan() {
    if (this.isScanning) {
      return;
    }

    this.isScanning = true;
    this.scanProgress = 0;
    this.scanMessage = '正在扫描...';

    try {
      // 创建 Worker
      this.scannerWorker = new worker.ThreadWorker('entry/ets/workers/Scanner.ets');
      
      // 监听 Worker 消息
      this.scannerWorker.onmessage = (e: MessageEvents): void => {
        const data: Record<string, string | number | boolean | TrackInfo[]> = e.data as Record<string, string | number | boolean | TrackInfo[]>;
        
        if (data.type === 'progress') {
          const scannedCount = data.scannedCount as number;
          const foundCount = data.foundCount as number;
          this.scanProgress = (scannedCount / foundCount) * 100;
          this.scanMessage = `已扫描 ${scannedCount}/${foundCount} 首歌曲`;
        } else if (data.type === 'batch') {
          // 批量插入数据库
          this.insertTracksBatch(data.tracks as Object[]);
        } else if (data.type === 'completed') {
          this.isScanning = false;
          const insertedCount = data.insertedCount as number;
          this.scanMessage = `扫描完成，共找到 ${insertedCount} 首歌曲`;
          try {
            promptAction.showToast({ message: this.scanMessage });
          } catch (err) {
            console.error('显示 Toast 失败:', err);
          }
          this.loadData();
        } else if (data.type === 'error') {
          this.isScanning = false;
          const errorMsg = data.error as string;
          this.scanMessage = '扫描失败: ' + errorMsg;
          try {
            promptAction.showToast({ message: this.scanMessage });
          } catch (err) {
            console.error('显示 Toast 失败:', err);
          }
        }
      };

      // 启动扫描 - 只扫描应用沙箱目录（有权限）
      const scanDirs: string[] = [];
      
      // 应用沙箱 files/music 目录
      if (this.appContext) {
        scanDirs.push(this.appContext.filesDir + '/music');
      }
      
      console.info('扫描目录:', JSON.stringify(scanDirs));
      
      this.scannerWorker.postMessage({
        type: 'start',
        options: {
          directories: scanDirs,
          recursive: true
        }
      });
    } catch (err) {
      this.isScanning = false;
      this.scanMessage = '启动扫描失败';
      console.error('启动扫描失败:', err);
    }
  }

  private async insertTracksBatch(tracksData: Object[]) {
    try {
      // Worker 传递的数据是普通对象，需要转换为 TrackInfo 实例
      const tracks: TrackInfo[] = [];
      for (const data of tracksData) {
        const trackData = data as Record<string, string | number>;
        console.info(`接收到歌曲数据: title=${trackData.title}, filePath=${trackData.filePath}`);
        
        const track = new TrackInfo({
          title: trackData.title as string || '未知歌曲',
          artist: trackData.artist as string || '未知歌手',
          album: trackData.album as string || '未知专辑',
          duration: trackData.duration as number || 0,
          filePath: trackData.filePath as string || '',
          coverUri: trackData.coverUri as string || '',
          addedAt: trackData.addedAt as number || Date.now()
        });
        tracks.push(track);
      }
      
      if (tracks.length > 0) {
        const count = await this.database.batchInsertTracks(tracks);
        console.info(`成功插入 ${count} 首歌曲`);
      }
    } catch (err) {
      console.error('批量插入歌曲失败:', err);
    }
  }

  private async navigateToPlayer() {
    try {
      await router.pushUrl({ url: 'pages/Player' });
    } catch (err) {
      console.error('导航到播放器失败:', err);
    }
  }

  private async navigateToSearch() {
    try {
      await router.pushUrl({ url: 'pages/Search' });
    } catch (err) {
      console.error('导航到搜索页失败:', err);
    }
  }

  private async navigateToLocalMusic() {
    try {
      await router.pushUrl({ url: 'pages/LocalMusic' });
    } catch (err) {
      console.error('导航到本地歌曲页失败:', err);
    }
  }

  private async navigateToFavorite() {
    try {
      await router.pushUrl({ url: 'pages/FavoriteMusic' });
    } catch (err) {
      console.error('导航到我喜欢的音乐失败:', err);
    }
  }

  private async navigateToRecentPlay() {
    try {
      await router.pushUrl({ url: 'pages/RecentPlay' });
    } catch (err) {
      console.error('导航到最近播放失败:', err);
    }
  }

  private playTrack(track: TrackInfo) {
    // 设置播放队列并播放
    this.audioSvc.setPlayQueue(this.recentTracks);
    this.audioSvc.loadTrack(track);
  }

  @Builder
  MenuItemBuilder(item: MenuItem) {
    Row() {
      Image(item.icon)
        .width(24)
        .height(24)
        .fillColor('#FF4081')
        .margin({ right: 16 })

      Column() {
        Text(item.title)
          .fontSize(16)
          .fontColor('#333333')
          .width('100%')

        if (item.subtitle) {
          Text(item.subtitle)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.count !== undefined) {
        Text(`${item.count}首`)
          .fontSize(14)
          .fontColor('#999999')
          .margin({ right: 8 })
      }

      Image($r('app.media.icon_arrow_right'))
        .width(16)
        .height(16)
        .fillColor('#CCCCCC')
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .onClick(item.onClick)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶部导航栏
        Row() {
          // 菜单按钮
          Button() {
            Image($r('app.media.icon_menu'))
              .width(24)
              .height(24)
              .fillColor('#333333')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(44)
          .height(44)

          // 搜索框
          Row() {
            Image($r('app.media.icon'))
              .width(20)
              .height(20)
              .fillColor('#999999')
              .margin({ left: 12 })

            Text('搜索音乐')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .height(40)
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .borderRadius(20)
          .margin({ left: 12, right: 12 })
          .onClick(() => this.navigateToSearch())

          // 设置按钮
          Button() {
            Image($r('app.media.icon_setting'))
              .width(24)
              .height(24)
              .fillColor('#333333')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(44)
          .height(44)
        }
        .width('100%')
        .height(80)
        .padding({ left: 8, right: 8 , top: 40})

        // 内容区域
        Scroll() {
          Column({ space: 16 }) {
            // 推荐歌单轮播（简化版）
            Swiper() {
              ForEach([1, 2, 3], (item: number) => {
                Column() {
                  Text(`推荐歌单 ${item}`)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .width('100%')
                .height(160)
                .backgroundColor(item === 1 ? '#FF4081' : item === 2 ? '#7C4DFF' : '#448AFF')
                .borderRadius(12)
                .justifyContent(FlexAlign.Center)
              })
            }
            .height(160)
            .itemSpace(12)
            .padding({ left: 16, right: 16 })

            // 我的本地音乐
            Column({ space: 0 }) {
              Text('我的本地音乐')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .width('100%')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })

              // 功能菜单
              this.MenuItemBuilder({
                icon: $r('app.media.icon_local_music'),
                title: '本地全盘扫描',
                subtitle: this.isScanning ? this.scanMessage : '扫描设备中的音频文件',
                onClick: (): void => { this.startScan(); }
              })

              Divider().padding({ left: 56 })

              this.MenuItemBuilder({
                icon: $r('app.media.icon_favorite'),
                title: '我喜欢的音乐',
                subtitle: '收藏的歌曲',
                count: this.favoritePlaylist?.trackCount || 0,
                onClick: (): void => { this.navigateToFavorite(); }
              })

              Divider().padding({ left: 56 })

              this.MenuItemBuilder({
                icon: $r('app.media.icon_local_music'),
                title: '本地歌曲',
                subtitle: '所有本地音乐',
                count: this.trackCount,
                onClick: (): void => { this.navigateToLocalMusic(); }
              })

              Divider().padding({ left: 56 })

              this.MenuItemBuilder({
                icon: $r('app.media.icon_recent'),
                title: '最近播放',
                subtitle: '最近听过的歌曲',
                count: this.recentTracks.length,
                onClick: (): void => { this.navigateToRecentPlay(); }
              })
            }
            .width('100%')
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ left: 16, right: 16 })

            // 最近播放列表
            if (this.recentTracks.length > 0) {
              Column({ space: 0 }) {
                Row() {
                  Text('最近播放')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')

                  Text('查看全部')
                    .fontSize(14)
                    .fontColor('#FF4081')
                    .onClick(() => {})
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .padding({ left: 16, right: 16, top: 16, bottom: 8 })

                // 歌曲列表（简化显示前5首）
                ForEach(this.recentTracks.slice(0, 5), (track: TrackInfo, index: number) => {
                  Row() {
                    Text((index + 1).toString())
                      .fontSize(14)
                      .fontColor('#999999')
                      .width(24)
                      .textAlign(TextAlign.Center)

                    Column() {
                      Text(track.title)
                        .fontSize(14)
                        .fontColor('#333333')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')

                      Text(track.artist)
                        .fontSize(12)
                        .fontColor('#999999')
                        .margin({ top: 2 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: 12 })

                    Text(track.formattedDuration)
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                  .width('100%')
                  .height(56)
                  .padding({ left: 16, right: 16 })
                  .onClick(() => this.playTrack(track))
                })
              }
              .width('100%')
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .margin({ left: 16, right: 16 })
            }

            // 底部留白（给迷你播放器）
            Blank().height(80)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')

      // 迷你播放条
      Column() {
        MiniPlayer({
          onExpand: (): void => { this.navigateToPlayer(); }
        })
      }
      .width('100%')
      .position({ bottom: 0 })
    }
    .width('100%')
    .height('100%')
  }
}
