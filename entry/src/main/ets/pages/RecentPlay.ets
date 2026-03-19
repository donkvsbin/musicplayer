/**
 * 最近播放页面
 */

import { router } from '@kit.ArkUI';
import { TrackInfo } from '../models/TrackInfo';
import { Database } from '../services/Database';
import { AudioSvc } from '../services/AudioSvc';
import { TrackItem } from '../views/TrackItem';
import { MiniPlayer } from '../views/MiniPlayer';

@Entry
@Component
struct RecentPlayPage {
  @State private tracks: TrackInfo[] = [];
  @State private isLoading: boolean = true;
  @State private currentTrackId: number = -1;

  private database: Database = Database.getInstance();
  private audioSvc: AudioSvc = AudioSvc.getInstance();

  aboutToAppear() {
    this.loadTracks();
  }

  private async loadTracks() {
    try {
      this.isLoading = true;
      // 获取所有歌曲（按添加时间倒序作为最近播放）
      const allTracks = await this.database.getAllTracks();
      this.tracks = allTracks;

      const currentTrack = this.audioSvc.getCurrentTrack();
      if (currentTrack) {
        this.currentTrackId = currentTrack.id;
      }
    } catch (err) {
      console.error('加载最近播放失败:', err);
    } finally {
      this.isLoading = false;
    }
  }

  private playTrack(track: TrackInfo) {
    const trackIndex = this.tracks.findIndex(t => t.id === track.id);
    this.audioSvc.setPlayQueue(this.tracks, trackIndex >= 0 ? trackIndex : 0, '最近播放');
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
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶部导航栏
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
          .onClick((): void => { this.navigateBack(); })

          Text('最近播放')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(44).height(80)
        }
        .width('100%')
        .height(85)
        .padding({ left: 8, right: 8 ,top:30})
        .backgroundColor('#FFFFFF')

        // 歌曲数量
        Row() {
          Image($r('app.media.icon_recent'))
            .width(16)
            .height(16)
            .fillColor('#FF4081')
            .margin({ right: 6 })
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
            Image($r('app.media.icon_recent'))
              .width(80)
              .height(80)
              .fillColor('#CCCCCC')
              .margin({ bottom: 16 })

            Text('暂无播放记录')
              .fontSize(16)
              .fontColor('#999999')
              .margin({ bottom: 8 })

            Text('扫描并播放本地音乐后会显示在这里')
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
          .padding({ bottom: 64 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')

      // 迷你播放条
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
  }
}
