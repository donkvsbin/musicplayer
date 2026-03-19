/**
 * 全屏播放详情页
 */

import { router } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { AudioSvc } from '../services/AudioSvc';
import { Database } from '../services/Database';
import { TrackInfo } from '../models/TrackInfo';

import { PlayMode, PlayerState, DEFAULT_PLAYLIST_FAVORITE } from '../constants/AppConstants';
import { TimeUtil } from '../utils/TimeUtil';
import { CoverExtractor } from '../utils/CoverExtractor';

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
  @State private coverPixelMap: image.PixelMap | null = null;
  @State private showPlaylist: boolean = false;
  @State private playlist: TrackInfo[] = [];
  @State private playlistName: string = '';

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
    this.playlistName = this.audioSvc.getCurrentPlaylistName();

    // 检查是否已收藏
    this.checkFavorite();

    // 提取封面
    this.loadCover();
  }
  
  /**
   * 加载当前歌曲的封面
   */
  private async loadCover() {
    if (!this.currentTrack || !this.currentTrack.filePath) {
      this.coverPixelMap = null;
      return;
    }
    
    // 先检查缓存
    const cachedCover = CoverExtractor.getCachedCover(this.currentTrack.filePath);
    if (cachedCover) {
      this.coverPixelMap = cachedCover;
      return;
    }
    
    // 提取封面
    try {
      const pixelMap = await CoverExtractor.extractCoverPixelMap(this.currentTrack.filePath);
      this.coverPixelMap = pixelMap;
      console.info(`[Player] 封面加载完成: ${pixelMap ? '成功' : '无封面'}`);
    } catch (err) {
      console.error('[Player] 封面加载失败:', err);
      this.coverPixelMap = null;
    }
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

  private formatTime(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  private openPlaylist() {
    this.playlist = this.audioSvc.getPlayQueue();
    animateTo({ duration: 250 }, () => {
      this.showPlaylist = true;
    });
  }

  private async playTrackFromPlaylist(track: TrackInfo) {
    try {
      await this.audioSvc.loadTrack(track);
      this.audioSvc.play();
      animateTo({ duration: 250 }, () => {
        this.showPlaylist = false;
      });
    } catch (err) {
      console.error('播放歌曲失败:', err);
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
          .onClick(async () => {
            try {
              await router.back();
            } catch (err) {
              console.error('返回失败:', err);
            }
          })

          Text('正在播放')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(44).height(44)
        }
        .width('100%')
        .height(70)
        .padding({ left: 8, right: 8, top: 40 })

        // 歌单名称
        if (this.playlistName) {
          Text(this.playlistName)
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }

        // 专辑封面区域
        Column() {
          if (this.coverPixelMap) {
            Image(this.coverPixelMap)
              .width(300)
              .height(300)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
              .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 10 })
          } else {
            Column() {
              Image($r('app.media.icon_music_note'))
                .width(100)
                .height(100)
                .fillColor('#CCCCCC')
            }
            .width(300)
            .height(300)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F5F5F5')
            .borderRadius(12)
            .shadow({ radius: 20, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 10 })
          }
        }
        .margin({ top: 40 })

        Blank()

        // 歌曲信息
        Column() {
          Text(this.currentTrack?.title || '未知歌曲')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          Text(this.currentTrack?.artist || '未知歌手')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .padding({ left: 32, right: 32 })
        .margin({ bottom: 24 })

        // 收藏按钮
        Button() {
          Image(this.isFavorite ? $r('app.media.icon_favorited') : $r('app.media.icon_favorite'))
            .width(28)
            .height(28)
            .fillColor(this.isFavorite ? '#FF4081' : '#999999')
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .width(48)
        .height(48)
        .onClick(() => this.toggleFavorite())
        .margin({ bottom: 24 })

        // 进度条
        Column() {
          Slider({
            value: this.duration > 0 ? this.currentTime / this.duration * 100 : 0,
            min: 0,
            max: 100,
            step: 0.1,
            style: SliderStyle.OutSet
          })
            .blockColor('#FF4081')
            .trackColor('#E0E0E0')
            .selectedColor('#FF4081')
            .showSteps(false)
            .showTips(false)
            .trackThickness(4)
            .blockSize({ width: 16, height: 16 })
            .onChange((value: number) => {
              const position = Math.floor(value / 100 * this.duration);
              this.seekToPosition(position);
            })

          Row() {
            Text(this.formatTime(this.currentTime))
              .fontSize(12)
              .fontColor('#999999')

            Blank()

            Text(this.formatTime(this.duration))
              .fontSize(12)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 4, right: 4 })
        }
        .width('100%')
        .padding({ left: 32, right: 32 })
        .margin({ bottom: 24 })

        // 播放控制区
        Row() {
          Button() {
            Image(this.getPlayModeIcon())
              .width(24)
              .height(24)
              .fillColor('#999999')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(48)
          .height(48)
          .onClick(() => this.togglePlayMode())

          Blank()

          Button() {
            Image($r('app.media.icon_previous'))
              .width(28)
              .height(28)
              .fillColor('#333333')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(56)
          .height(56)
          .onClick(() => this.previousTrack())

          Button() {
            Image(this.isPlaying ? $r('app.media.icon_pause') : $r('app.media.icon_play'))
              .width(36)
              .height(36)
              .fillColor('#FFFFFF')
          }
          .type(ButtonType.Circle)
          .backgroundColor('#FF4081')
          .width(72)
          .height(72)
          .shadow({ radius: 10, color: 'rgba(255,64,129,0.3)' })
          .onClick(() => this.togglePlay())

          Button() {
            Image($r('app.media.icon_next'))
              .width(28)
              .height(28)
              .fillColor('#333333')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(56)
          .height(56)
          .onClick(() => this.nextTrack())

          Blank()

          Button() {
            Image($r('app.media.icon_playlist'))
              .width(24)
              .height(24)
              .fillColor('#999999')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(48)
          .height(48)
          .onClick(() => this.openPlaylist())
        }
        .width('100%')
        .height(80)
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FAFAFA')

      // 底部播放列表
      if (this.showPlaylist) {
        // 半透明遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.5)')
          .onClick(() => {
            animateTo({ duration: 250 }, () => {
              this.showPlaylist = false;
            });
          })
          .transition(TransitionEffect.OPACITY)

        // 播放列表面板
        Column() {
          Row() {
            Text('播放列表')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
            Blank()
            Text(`${this.playlist.length} 首`)
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 12 })

          if (this.playlist.length === 0) {
            Column() {
              Text('播放列表为空')
                .fontSize(14)
                .fontColor('#999999')
            }
            .width('100%')
            .height(150)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 0 }) {
              ForEach(this.playlist, (track: TrackInfo) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(track.title || '未知歌曲')
                        .fontSize(15)
                        .fontColor(this.currentTrack?.id === track.id ? '#FF4081' : '#333333')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(track.artist || '未知歌手')
                        .fontSize(12)
                        .fontColor('#999999')
                        .margin({ top: 4 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (this.currentTrack?.id === track.id) {
                      Image($r('app.media.icon_playing'))
                        .width(20)
                        .height(20)
                        .fillColor('#FF4081')
                    }
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .onClick(() => { this.playTrackFromPlaylist(track); })
                }
              })
            }
            .width('100%')
            .height(250)
            .divider({ strokeWidth: 0.5, color: '#EEEEEE' })
          }
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 16, topRight: 16 })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.1)' })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 300 })),
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 300 }))
        ))
      }
    }
    .width('100%')
    .height('100%')
  }
}
