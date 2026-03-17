/**
 * 全屏播放详情页
 */

import { router } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { AudioSvc } from '../services/AudioSvc';
import { Database } from '../services/Database';
import { TrackInfo } from '../models/TrackInfo';
import { ProgressBar } from '../views/ProgressBar';
import { PlayMode, PlayerState, DEFAULT_PLAYLIST_FAVORITE } from '../constants/AppConstants';
import { TimeUtil } from '../utils/TimeUtil';

@Entry
@Component
struct Player {
  @State private currentTrack: TrackInfo | null = null;
  @State private isPlaying: boolean = false;
  @State private currentTime: number = 0;
  @State private duration: number = 0;
  @State private playMode: PlayMode = PlayMode.ORDER;
  @State private isFavorite: boolean = false;
  @State private rotationAngle: number = 0;
  @State private lyrics: string = '暂无歌词';

  private audioSvc: AudioSvc = AudioSvc.getInstance();
  private database: Database = Database.getInstance();
  private rotationTimer: number = -1;

  aboutToAppear() {
    // 初始化状态
    this.updatePlayerState();
    
    // 监听播放进度更新
    emitter.on({ eventId: 3 }, (eventData) => {
      const data = eventData.data as Record<string, number>;
      console.info(`Player 收到进度更新: currentTime=${data.currentTime}, duration=${data.duration}`);
      this.currentTime = data.currentTime;
      this.duration = data.duration;
    });

    // 监听播放状态变化
    emitter.on({ eventId: 2 }, () => {
      this.updatePlayerState();
    });

    // 监听歌曲变化
    emitter.on({ eventId: 1 }, () => {
      this.updatePlayerState();
    });

    // 启动唱片旋转动画
    this.startRotationAnimation();
  }

  aboutToDisappear() {
    // 停止旋转动画
    this.stopRotationAnimation();
  }

  private updatePlayerState() {
    this.currentTrack = this.audioSvc.getCurrentTrack();
    this.isPlaying = this.audioSvc.isPlaying();
    this.playMode = this.audioSvc.getPlayMode();
    this.currentTime = this.audioSvc.getCurrentPosition();
    this.duration = this.audioSvc.getDuration();
    
    // 检查是否已收藏
    this.checkFavorite();
  }

  private async checkFavorite() {
    if (!this.currentTrack) {
      this.isFavorite = false;
      return;
    }

    try {
      const favoritePlaylist = await this.database.getPlaylistByName(DEFAULT_PLAYLIST_FAVORITE);
      if (favoritePlaylist) {
        this.isFavorite = favoritePlaylist.hasTrack(this.currentTrack.id);
      }
    } catch (err) {
      console.error('检查收藏状态失败:', err);
    }
  }

  private async toggleFavorite() {
    if (!this.currentTrack) return;

    try {
      const favoritePlaylist = await this.database.getPlaylistByName(DEFAULT_PLAYLIST_FAVORITE);
      if (favoritePlaylist) {
        if (this.isFavorite) {
          await this.database.removeTrackFromPlaylist(favoritePlaylist.id, this.currentTrack.id);
          this.isFavorite = false;
        } else {
          // 先插入歌曲（如果不存在）
          if (this.currentTrack.id < 0) {
            const trackId = await this.database.insertTrack(this.currentTrack);
            this.currentTrack.id = trackId;
          }
          await this.database.addTrackToPlaylist(favoritePlaylist.id, this.currentTrack.id);
          this.isFavorite = true;
        }
      }
    } catch (err) {
      console.error('切换收藏状态失败:', err);
    }
  }

  private startRotationAnimation() {
    this.rotationTimer = setInterval(() => {
      if (this.isPlaying) {
        this.rotationAngle = (this.rotationAngle + 1) % 360;
      }
    }, 50);
  }

  private stopRotationAnimation() {
    if (this.rotationTimer !== -1) {
      clearInterval(this.rotationTimer);
      this.rotationTimer = -1;
    }
  }

  private togglePlay() {
    if (this.isPlaying) {
      this.audioSvc.pause();
    } else {
      this.audioSvc.play();
    }
  }

  private previousTrack() {
    this.audioSvc.previous();
  }

  private nextTrack() {
    this.audioSvc.next();
  }

  private togglePlayMode() {
    const newMode = this.audioSvc.togglePlayMode();
    this.playMode = newMode;
  }

  private seekToPosition(position: number) {
    this.audioSvc.seekTo(position);
  }

  private getPlayModeIcon(): Resource {
    switch (this.playMode) {
      case PlayMode.RANDOM:
        return $r('app.media.icon_random');
      case PlayMode.SINGLE_LOOP:
        return $r('app.media.icon_single_loop');
      case PlayMode.ORDER:
      default:
        return $r('app.media.icon_order');
    }
  }

  private getPlayModeText(): string {
    switch (this.playMode) {
      case PlayMode.RANDOM:
        return '随机播放';
      case PlayMode.SINGLE_LOOP:
        return '单曲循环';
      case PlayMode.ORDER:
      default:
        return '顺序播放';
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 背景层 - 专辑封面模糊
      if (this.currentTrack?.coverUri) {
        Image(this.currentTrack.coverUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(60)
          .brightness(0.6)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#2C2C2C')
      }

      // 前景内容层
      Column() {
        // 顶部导航栏
        Row() {
          // 下拉收起按钮
          Button() {
            Image($r('app.media.icon_back'))
              .width(24)
              .height(24)
              .fillColor('#FFFFFF')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(44)
          .height(44)
          .onClick(async () => {
            try {
              await router.back();
            } catch (err) {
              console.error('返回失败:', err);
            }
          })

        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 ,top: 40})
        .backgroundColor('transparent')

        // 中间内容区域
        Column() {
          // 唱片封面
          Stack() {
            // 外圈装饰
            Circle()
              .width(280)
              .height(280)
              .fill('rgba(255,255,255,0.1)')
              .stroke('rgba(255,255,255,0.2)')
              .strokeWidth(2)

            // 唱片
            Stack() {
              if (this.currentTrack?.coverUri) {
                Image(this.currentTrack.coverUri)
                  .width(260)
                  .height(260)
                  .borderRadius(130)
                  .objectFit(ImageFit.Cover)
                  .rotate({ angle: this.rotationAngle })
              } else {
                Column() {
                  Image($r('app.media.icon_music_note'))
                    .width(80)
                    .height(80)
                    .fillColor('rgba(255,255,255,0.5)')
                }
                .width(260)
                .height(260)
                .backgroundColor('rgba(255,255,255,0.1)')
                .borderRadius(130)
                .justifyContent(FlexAlign.Center)
              }

              // 中心孔
              Circle()
                .width(60)
                .height(60)
                .fill('#2C2C2C')

              Circle()
                .width(20)
                .height(20)
                .fill('rgba(255,255,255,0.2)')
            }
            .width(260)
            .height(260)
          }
          .width(280)
          .height(280)
          .margin({ top: 40 })

          // 歌词预览
          Text(this.lyrics)
            .fontSize(14)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 32 })
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })

          // 空白填充
          Blank()

          // 歌曲信息
          Column() {
            Text(this.currentTrack?.title || '未知歌曲')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Center)

            Text(this.currentTrack?.artist || '未知歌手')
              .fontSize(16)
              .fontColor('rgba(255,255,255,0.7)')
              .margin({ top: 8 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          .margin({ bottom: 24 })

          // 交互按钮区
          Row({ space: 32 }) {
            // 收藏按钮
            Button() {
              Image(this.isFavorite ? $r('app.media.icon_favorited') : $r('app.media.icon_favorite'))
                .width(28)
                .height(28)
                .fillColor(this.isFavorite ? '#FF4081' : '#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(48)
            .height(48)
            .onClick(() => this.toggleFavorite())
          }
          .margin({ bottom: 24 })

          // 进度条
          ProgressBar({
            currentTime: this.currentTime,
            duration: this.duration,
            progressColor: '#FF4081',
            barBgColor: 'rgba(255,255,255,0.3)',
            onSeek: (position: number): void => { this.seekToPosition(position); }
          })

          // 播放控制区
          Row() {
            // 播放模式
            Button() {
              Image(this.getPlayModeIcon())
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(48)
            .height(48)
            .onClick(() => this.togglePlayMode())

            Blank()

            // 上一首
            Button() {
              Image($r('app.media.icon_previous'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(56)
            .height(56)
            .onClick(() => this.previousTrack())

            // 播放/暂停
            Button() {
              Image(this.isPlaying ? $r('app.media.icon_pause') : $r('app.media.icon_play'))
                .width(48)
                .height(48)
                .fillColor('#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('#FF4081')
            .width(72)
            .height(72)
            .onClick(() => this.togglePlay())

            // 下一首
            Button() {
              Image($r('app.media.icon_next'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(56)
            .height(56)
            .onClick(() => this.nextTrack())

            Blank()

            // 播放列表
            Button() {
              Image($r('app.media.icon_playlist'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
            }
            .type(ButtonType.Circle)
            .backgroundColor('transparent')
            .width(48)
            .height(48)
          }
          .width('100%')
          .height(80)
          .padding({ left: 24, right: 24 })
          .margin({ bottom: 16 })
          .backgroundColor('transparent')
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('transparent')
    }
    .width('100%')
    .height('100%')
  }
}
