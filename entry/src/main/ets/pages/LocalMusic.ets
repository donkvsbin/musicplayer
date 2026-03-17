/**
 * 本地歌曲页面
 * 显示所有本地音乐列表
 */

import { router } from '@kit.ArkUI';
import { TrackInfo } from '../models/TrackInfo';
import { Database } from '../services/Database';
import { AudioSvc } from '../services/AudioSvc';
import { TrackItem } from '../views/TrackItem';
import { MiniPlayer } from '../views/MiniPlayer';

@Entry
@Component
struct LocalMusicPage {
  @State private tracks: TrackInfo[] = [];
  @State private isLoading: boolean = true;
  @State private currentTrackId: number = -1;

  private database: Database = Database.getInstance();
  private audioSvc: AudioSvc = AudioSvc.getInstance();

  aboutToAppear() {
    this.initAndLoad();
  }

  private async initAndLoad() {
    try {
      // 确保 AudioSvc 已初始化
      const context = getContext(this);
      await this.audioSvc.init(context);
      console.info('AudioSvc 初始化检查完成');
    } catch (err) {
      console.error('AudioSvc 初始化失败:', err);
    }
    
    this.loadTracks();
  }

  private async loadTracks() {
    try {
      this.isLoading = true;
      this.tracks = await this.database.getAllTracks();
      
      // 获取当前播放的歌曲
      const currentTrack = this.audioSvc.getCurrentTrack();
      if (currentTrack) {
        this.currentTrackId = currentTrack.id;
      }
    } catch (err) {
      console.error('加载歌曲失败:', err);
    } finally {
      this.isLoading = false;
    }
  }

  private playTrack(track: TrackInfo) {
    console.info(`准备播放: ${track.title}, 文件路径: ${track.filePath}`);
    
    // 找到点击歌曲在列表中的索引
    const trackIndex = this.tracks.findIndex(t => t.id === track.id);
    
    // 设置播放队列为所有歌曲，并从点击的歌曲开始播放
    this.audioSvc.setPlayQueue(this.tracks, trackIndex >= 0 ? trackIndex : 0);
    
    this.currentTrackId = track.id;
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
      // 顶部导航栏
      Row() {
        // 返回按钮
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
        .onClick((): void => { this.navigateBack(); })

        // 标题
        Text('本地歌曲')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 占位
        Row().width(44).height(44)
      }
      .width('100%')
      .height(80)
      .padding({ left: 8, right: 8 ,top: 30})
      .backgroundColor('#FFFFFF')

      // 歌曲数量
      Row() {
        Text(`共 ${this.tracks.length} 首歌曲`)
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 歌曲列表
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.tracks.length === 0) {
        Column() {
          Image($r('app.media.icon_music_note'))
            .width(80)
            .height(80)
            .fillColor('#CCCCCC')
            .margin({ bottom: 16 })

          Text('暂无本地歌曲')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ bottom: 8 })

          Text('点击首页的"扫描本地音乐"添加歌曲')
            .fontSize(14)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.tracks, (track: TrackInfo, index: number) => {
            ListItem() {
              TrackItem({
                track: track,
                index: index + 1,
                isPlaying: this.currentTrackId === track.id,
                onTrackClick: (t: TrackInfo): void => { this.playTrack(t); }
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: '#EEEEEE' })
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
    .backgroundColor('#F5F5F5')
  }
}
