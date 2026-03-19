/**
 * 歌单详情页面
 * 显示歌单信息和歌曲列表
 */

import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { TrackInfo } from '../models/TrackInfo';
import { PlayList } from '../models/PlayList';
import { Database } from '../services/Database';
import { AudioSvc } from '../services/AudioSvc';
import { TrackItem } from '../views/TrackItem';
import { MiniPlayer } from '../views/MiniPlayer';
import { image } from '@kit.ImageKit';
import { CoverExtractor } from '../utils/CoverExtractor';

interface PopupStateEvent {
  isVisible: boolean;
}

@Entry
@Component
struct PlaylistDetailPage {
  @State private playlist: PlayList | null = null;
  @State private tracks: TrackInfo[] = [];
  @State private isLoading: boolean = true;
  @State private currentTrackId: number = -1;
  @State private playlistId: number = -1;
  @State private coverPixelMap: image.PixelMap | null = null;
  @State private showMenuPopup: boolean = false;
  @State private showEditPopup: boolean = false;
  @State private editName: string = '';
  @State private editDescription: string = '';

  private database: Database = Database.getInstance();
  private audioSvc: AudioSvc = AudioSvc.getInstance();

  aboutToAppear() {
    const params = router.getParams() as Record<string, number>;
    if (params && params.playlistId) {
      this.playlistId = params.playlistId;
    }
    this.loadPlaylistData();
  }
  
  onPageShow() {
    this.loadPlaylistData();
  }

  private async loadPlaylistData() {
    if (this.playlistId < 0) {
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      const playlists = await this.database.getAllPlaylists();
      this.playlist = playlists.find((p: PlayList): boolean => p.id === this.playlistId) || null;
      
      if (this.playlist) {
        this.tracks = await this.database.getPlaylistTracks(this.playlist.id);
        
        if (this.playlist.coverUri) {
          // TODO: 加载自定义封面
        } else if (this.tracks.length > 0 && this.tracks[0].filePath) {
          const firstTrack = this.tracks[0];
          const cachedCover = CoverExtractor.getCachedCover(firstTrack.filePath);
          if (cachedCover) {
            this.coverPixelMap = cachedCover;
          } else {
            try {
              const metadata = await CoverExtractor.extractMetadata(firstTrack.filePath);
              if (metadata.cover) {
                this.coverPixelMap = metadata.cover;
              }
            } catch (err) {
              console.error('加载封面失败:', err);
            }
          }
        }
      }
      
      const currentTrack = this.audioSvc.getCurrentTrack();
      if (currentTrack) {
        this.currentTrackId = currentTrack.id;
      }
    } catch (err) {
      console.error('加载歌单数据失败:', err);
    } finally {
      this.isLoading = false;
    }
  }

  private playTrack(track: TrackInfo) {
    const trackIndex = this.tracks.findIndex(t => t.id === track.id);
    this.audioSvc.setPlayQueue(this.tracks, trackIndex >= 0 ? trackIndex : 0, this.playlist?.name || '');
    this.currentTrackId = track.id;
  }

  private async navigateBack() {
    try {
      await router.back();
    } catch (err) {
      console.error('返回失败:', err);
    }
  }

  private openEditForm() {
    if (this.playlist) {
      this.editName = this.playlist.name;
      this.editDescription = this.playlist.description || '';
      this.showMenuPopup = false;
      this.showEditPopup = true;
    }
  }

  private async updatePlaylist() {
    if (!this.playlist || !this.editName.trim()) {
      promptAction.showToast({ message: '请输入歌单名称' });
      return;
    }

    try {
      await this.database.updatePlaylist(this.playlist.id, this.editName.trim(), this.editDescription.trim());
      this.showEditPopup = false;
      promptAction.showToast({ message: '修改成功' });
      this.loadPlaylistData();
    } catch (err) {
      console.error('修改歌单失败:', err);
      promptAction.showToast({ message: '修改失败' });
    }
  }

  private async deletePlaylist() {
    if (!this.playlist) {
      return;
    }

    try {
      this.showMenuPopup = false;
      await this.database.deletePlaylist(this.playlist.id);
      promptAction.showToast({ message: '歌单已删除' });
      router.back();
    } catch (err) {
      console.error('删除歌单失败:', err);
      promptAction.showToast({ message: '删除失败' });
    }
  }

  @Builder
  MenuPopupBuilder() {
    Column() {
      Row() {
        Image($r('app.media.icon_setting'))
          .width(20)
          .height(20)
          .fillColor('#333333')
          .margin({ right: 12 })
        Text('编辑歌单')
          .fontSize(15)
          .fontColor('#333333')
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.openEditForm();
      })

      Divider().margin({ left: 48 })

      Row() {
        Image($r('app.media.icon_delete'))
          .width(20)
          .height(20)
          .fillColor('#FF4444')
          .margin({ right: 12 })
        Text('删除歌单')
          .fontSize(15)
          .fontColor('#FF4444')
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.deletePlaylist();
      })
    }
    .width(140)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)' })
  }

  build() {
    Stack() {
      // 主内容
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

          Text('歌单详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button() {
            Image($r('app.media.icon_more'))
              .width(24)
              .height(24)
              .fillColor('#333333')
          }
          .type(ButtonType.Circle)
          .backgroundColor('transparent')
          .width(44)
          .height(44)
          .onClick((): void => { this.showMenuPopup = true; })
          .bindPopup(this.showMenuPopup, {
            placement: Placement.BottomRight,
            showInSubWindow: false,
            onStateChange: (e: PopupStateEvent): void => {
              if (!e.isVisible) {
                this.showMenuPopup = false;
              }
            },
            builder: (): void => this.MenuPopupBuilder()
          })
        }
        .width('100%')
        .height(80)
        .padding({ left: 8, right: 8, top: 30 })
        .backgroundColor('#FFFFFF')

        // 歌单信息区域
        Column() {
          Row() {
            if (this.coverPixelMap) {
              Image(this.coverPixelMap)
                .width(100)
                .height(100)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            } else {
              Column() {
                Image($r('app.media.play_list'))
                  .width(48)
                  .height(48)
                  .fillColor('#CCCCCC')
              }
              .width(100)
              .height(100)
              .backgroundColor('#F0F0F0')
              .borderRadius(8)
              .justifyContent(FlexAlign.Center)
            }

            Column() {
              Text(this.playlist?.name || '未知歌单')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(this.playlist?.description || '暂无描述')
                .fontSize(13)
                .fontColor('#999999')
                .margin({ top: 8 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(`${this.tracks.length} 首歌曲`)
                .fontSize(12)
                .fontColor('#CCCCCC')
                .margin({ top: 6 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .backgroundColor('#FFFFFF')

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

            Text('暂无歌曲')
              .fontSize(16)
              .fontColor('#999999')
              .margin({ bottom: 16 })

            Button('添加歌曲')
              .width(120)
              .height(40)
              .backgroundColor('#FF4081')
              .fontColor('#FFFFFF')
              .borderRadius(20)
              .onClick(async () => {
                try {
                  await router.pushUrl({
                    url: 'pages/AddToPlaylist',
                    params: {
                      playlistId: this.playlistId,
                      playlistName: this.playlist?.name || ''
                    }
                  });
                } catch (err) {
                  console.error('跳转失败:', err);
                }
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            List({ space: 0 }) {
              ForEach(this.tracks, (track: TrackInfo, index: number) => {
                ListItem() {
                  TrackItem({
                    track: track,
                    index: -1,
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

            Button() {
              Image($r('app.media.icon_favorite2'))
                .width(28)
                .height(28)
                .fillColor('#FFFFFF')
            }
            .width(56)
            .height(56)
            .backgroundColor('#FF4081')
            .borderRadius(28)
            .position({ x: '100%', y: '100%' })
            .translate({ x: -72, y: -136 })
            .shadow({ radius: 8, color: 'rgba(255,64,129,0.3)' })
            .onClick(async () => {
              try {
                await router.pushUrl({
                  url: 'pages/AddToPlaylist',
                  params: {
                    playlistId: this.playlistId,
                    playlistName: this.playlist?.name || ''
                  }
                });
              } catch (err) {
                console.error('跳转失败:', err);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
        }

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
      .backgroundColor('#F5F5F5')

      // 编辑表单弹窗
      if (this.showEditPopup) {
        Stack({ alignContent: Alignment.Center }) {
          // 遮罩层
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showEditPopup = false;
            })

          // 编辑表单
          Column() {
            Text('编辑歌单')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })

            Column() {
              Text('名称')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ text: this.editName })
                .height(44)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .margin({ top: 8 })
                .onChange((value: string): void => { this.editName = value; })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Column() {
              Text('描述')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ text: this.editDescription })
                .height(44)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .margin({ top: 8 })
                .onChange((value: string): void => { this.editDescription = value; })
            }
            .width('100%')
            .margin({ bottom: 24 })

            Row() {
              Button('取消')
                .width(100)
                .height(40)
                .backgroundColor('#F0F0F0')
                .fontColor('#666666')
                .borderRadius(20)
                .onClick(() => {
                  this.showEditPopup = false;
                })

              Blank()

              Button('保存')
                .width(100)
                .height(40)
                .backgroundColor('#FF4081')
                .fontColor('#FFFFFF')
                .borderRadius(20)
                .onClick(() => {
                  this.updatePlaylist();
                })
            }
            .width('100%')
          }
          .width('85%')
          .padding(24)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)' })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
