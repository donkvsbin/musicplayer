/**
 * 歌曲列表项组件
 */

import { TrackInfo } from '../models/TrackInfo';

@Component
export struct TrackItem {
  // 歌曲信息
  @ObjectLink track: TrackInfo;
  // 是否正在播放
  @Prop isPlaying: boolean = false;
  // 序号（可选）
  @Prop index: number = -1;
  // 是否显示更多按钮
  @Prop showMore: boolean = true;
  // 点击回调
  onTrackClick?: (track: TrackInfo) => void;
  // 更多按钮点击回调
  onMoreClick?: (track: TrackInfo) => void;

  build() {
    Row() {
      // 序号或播放图标
      if (this.index >= 0) {
        if (this.isPlaying) {
          // 正在播放动画
          Row() {
            Column()
              .width(3)
              .height(12)
              .backgroundColor('#FF4081')
              .animation({
                duration: 500,
                iterations: -1,
                playMode: PlayMode.Alternate,
                curve: Curve.EaseInOut
              })
            Column()
              .width(3)
              .height(16)
              .backgroundColor('#FF4081')
              .margin({ left: 2 })
              .animation({
                duration: 600,
                iterations: -1,
                playMode: PlayMode.Alternate,
                curve: Curve.EaseInOut
              })
            Column()
              .width(3)
              .height(10)
              .backgroundColor('#FF4081')
              .margin({ left: 2 })
              .animation({
                duration: 450,
                iterations: -1,
                playMode: PlayMode.Alternate,
                curve: Curve.EaseInOut
              })
          }
          .width(30)
          .justifyContent(FlexAlign.Center)
        } else {
          Text(this.index.toString())
            .fontSize(16)
            .fontColor('#999999')
            .width(30)
            .textAlign(TextAlign.Center)
        }
      }

      // 封面图
      Stack() {
        if (this.track.coverUri) {
          Image(this.track.coverUri)
            .width(48)
            .height(48)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)
        } else {
          // 默认封面
          Column() {
            Image($r('app.media.icon_music_note'))
              .width(24)
              .height(24)
              .fillColor('#CCCCCC')
          }
          .width(48)
          .height(48)
          .backgroundColor('#F0F0F0')
          .borderRadius(4)
          .justifyContent(FlexAlign.Center)
        }

        // 正在播放指示器
        if (this.isPlaying) {
          Column() {
            Image($r('app.media.icon_play'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
          }
          .width(48)
          .height(48)
          .backgroundColor('rgba(0,0,0,0.5)')
          .borderRadius(4)
          .justifyContent(FlexAlign.Center)
        }
      }
      .margin({ left: this.index >= 0 ? 8 : 0 })

      // 歌曲信息
      Column() {
        // 歌曲名
        Text(this.track.title)
          .fontSize(16)
          .fontWeight(this.isPlaying ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.isPlaying ? '#FF4081' : '#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 歌手名
        Text(this.track.artist)
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 8 })

      // 时长
      Text(this.track.formattedDuration)
        .fontSize(12)
        .fontColor('#999999')
        .width(45)
        .textAlign(TextAlign.End)

      // 更多按钮
      if (this.showMore) {
        Button() {
          Image($r('app.media.icon_arrow_right'))
            .width(20)
            .height(20)
            .fillColor('#999999')
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .width(40)
        .height(40)
        .onClick(() => {
          if (this.onMoreClick) {
            this.onMoreClick(this.track);
          }
        })
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 8 })
    .backgroundColor(this.isPlaying ? 'rgba(255,64,129,0.05)' : '#FFFFFF')
    .onClick(() => {
      if (this.onTrackClick) {
        this.onTrackClick(this.track);
      }
    })
  }
}
