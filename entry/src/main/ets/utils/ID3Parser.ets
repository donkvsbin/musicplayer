/**
 * ID3 标签解析器
 * 用于从音频文件中提取元数据信息
 */

import { fileIo } from '@kit.CoreFileKit';
import { TrackInfo, TrackInfoOptions } from '../models/TrackInfo';

/**
 * ID3 标签信息
 */
export interface ID3Info {
  title?: string;
  artist?: string;
  album?: string;
  year?: string;
  genre?: string;
  trackNumber?: string;
  duration?: number;
  coverData?: ArrayBuffer;
}

/**
 * ID3 标签解析器
 */
export class ID3Parser {
  /**
   * 解析音频文件的 ID3 标签
   * @param filePath 音频文件路径
   * @returns ID3 信息
   */
  static async parseID3(filePath: string): Promise<ID3Info> {
    const info: ID3Info = {};
    
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      
      try {
        // 读取文件头部 (前 10KB 通常包含 ID3 标签)
        const buffer = new ArrayBuffer(10240);
        const readLen = fileIo.readSync(file.fd, buffer, { offset: 0, length: 10240 });
        
        if (readLen > 0) {
          const dataView = new DataView(buffer);
          
          // 检查 ID3v2 标签
          const id3Header = ID3Parser.readString(dataView, 0, 3);
          if (id3Header === 'ID3') {
            const id3v2Info = ID3Parser.parseID3v2(dataView);
            // 手动合并对象（避免使用 Object.assign）
            if (id3v2Info.title) info.title = id3v2Info.title;
            if (id3v2Info.artist) info.artist = id3v2Info.artist;
            if (id3v2Info.album) info.album = id3v2Info.album;
            if (id3v2Info.year) info.year = id3v2Info.year;
            if (id3v2Info.genre) info.genre = id3v2Info.genre;
            if (id3v2Info.trackNumber) info.trackNumber = id3v2Info.trackNumber;
            if (id3v2Info.duration) info.duration = id3v2Info.duration;
            if (id3v2Info.coverData) info.coverData = id3v2Info.coverData;
          }
          
          // 如果 ID3v2 没有解析到基本信息，尝试 ID3v1
          if (!info.title || !info.artist) {
            // ID3v1 标签在文件最后 128 字节
            const stat = fileIo.statSync(filePath);
            if (stat.size > 128) {
              const id3v1Buffer = new ArrayBuffer(128);
              fileIo.readSync(file.fd, id3v1Buffer, { offset: stat.size - 128, length: 128 });
              const id3v1DataView = new DataView(id3v1Buffer);
              const id3v1Info = ID3Parser.parseID3v1(id3v1DataView);
              
              // 合并信息，ID3v2 优先级更高
              if (!info.title && id3v1Info.title) info.title = id3v1Info.title;
              if (!info.artist && id3v1Info.artist) info.artist = id3v1Info.artist;
              if (!info.album && id3v1Info.album) info.album = id3v1Info.album;
              if (!info.year && id3v1Info.year) info.year = id3v1Info.year;
              if (!info.genre && id3v1Info.genre) info.genre = id3v1Info.genre;
            }
          }
        }
        
        // 获取音频时长（通过文件属性或估算）
        if (!info.duration) {
          info.duration = await ID3Parser.estimateDuration(filePath);
        }
        
      } finally {
        fileIo.closeSync(file);
      }
      
    } catch (err) {
      console.error('解析 ID3 标签失败:', err);
    }
    
    return info;
  }

  /**
   * 解析 ID3v2 标签
   */
  private static parseID3v2(dataView: DataView): ID3Info {
    const info: ID3Info = {};
    
    try {
      // ID3v2 版本
      const versionMajor = dataView.getUint8(3);
      const versionMinor = dataView.getUint8(4);
      
      // 标签大小（同步安全整数）
      const tagSize = ID3Parser.readSyncSafeInt(dataView, 6);
      
      // 扩展头部标志
      const flags = dataView.getUint8(5);
      const hasExtendedHeader = (flags & 0x40) !== 0;
      
      let offset = 10;
      
      // 跳过扩展头部
      if (hasExtendedHeader && versionMajor >= 3) {
        const extHeaderSize = dataView.getUint32(offset);
        offset += extHeaderSize + 4;
      }
      
      // 解析帧
      while (offset < tagSize + 10) {
        const frameId = ID3Parser.readString(dataView, offset, 4);
        
        // 遇到填充或结束
        if (frameId.charCodeAt(0) === 0) {
          break;
        }
        
        let frameSize: number;
        if (versionMajor >= 4) {
          frameSize = ID3Parser.readSyncSafeInt(dataView, offset + 4);
        } else {
          frameSize = dataView.getUint32(offset + 4);
        }
        
        const frameData = ID3Parser.readFrameData(dataView, offset + 10, frameSize);
        
        // 解析常用帧
        switch (frameId) {
          case 'TIT2':
            info.title = frameData;
            break;
          case 'TPE1':
          case 'TPE2':
            if (!info.artist) info.artist = frameData;
            break;
          case 'TALB':
            info.album = frameData;
            break;
          case 'TYER':
          case 'TDRC':
            info.year = frameData;
            break;
          case 'TCON':
            info.genre = frameData;
            break;
          case 'TRCK':
            info.trackNumber = frameData;
            break;
          case 'APIC':
            // 封面图片
            info.coverData = ID3Parser.extractCoverData(dataView, offset + 10, frameSize);
            break;
          case 'TLEN':
            // 时长（毫秒）
            const durationMs = parseInt(frameData, 10);
            if (!isNaN(durationMs) && durationMs > 0) {
              info.duration = durationMs;
            }
            break;
        }
        
        offset += 10 + frameSize;
      }
      
    } catch (err) {
      console.error('解析 ID3v2 失败:', err);
    }
    
    return info;
  }

  /**
   * 解析 ID3v1 标签
   */
  private static parseID3v1(dataView: DataView): ID3Info {
    const info: ID3Info = {};
    
    try {
      // 检查 ID3v1 标识
      const tag = ID3Parser.readString(dataView, 0, 3);
      if (tag !== 'TAG') {
        return info;
      }
      
      info.title = ID3Parser.readString(dataView, 3, 30).trim();
      info.artist = ID3Parser.readString(dataView, 33, 30).trim();
      info.album = ID3Parser.readString(dataView, 63, 30).trim();
      info.year = ID3Parser.readString(dataView, 93, 4).trim();
      info.genre = ID3Parser.readString(dataView, 127, 1);
      
    } catch (err) {
      console.error('解析 ID3v1 失败:', err);
    }
    
    return info;
  }

  /**
   * 从 DataView 读取字符串
   */
  private static readString(dataView: DataView, offset: number, length: number): string {
    const bytes: number[] = [];
    for (let i = 0; i < length; i++) {
      const byte = dataView.getUint8(offset + i);
      if (byte === 0) break;
      bytes.push(byte);
    }
    return String.fromCharCode(...bytes);
  }

  /**
   * 读取同步安全整数
   */
  private static readSyncSafeInt(dataView: DataView, offset: number): number {
    return (dataView.getUint8(offset) << 21) |
           (dataView.getUint8(offset + 1) << 14) |
           (dataView.getUint8(offset + 2) << 7) |
           dataView.getUint8(offset + 3);
  }

  /**
   * 读取帧数据（处理编码）
   */
  private static readFrameData(dataView: DataView, offset: number, length: number): string {
    if (length < 1) return '';
    
    const encoding = dataView.getUint8(offset);
    const textStart = offset + 1;
    const textLength = length - 1;
    
    // ISO-8859-1
    if (encoding === 0) {
      return ID3Parser.readString(dataView, textStart, textLength).trim();
    }
    // UTF-16 with BOM
    else if (encoding === 1) {
      return ID3Parser.readUTF16String(dataView, textStart, textLength);
    }
    // UTF-16BE without BOM
    else if (encoding === 2) {
      return ID3Parser.readUTF16BEString(dataView, textStart, textLength);
    }
    // UTF-8
    else if (encoding === 3) {
      return ID3Parser.readUTF8String(dataView, textStart, textLength);
    }
    
    return '';
  }

  /**
   * 读取 UTF-16 字符串
   */
  private static readUTF16String(dataView: DataView, offset: number, length: number): string {
    if (length < 2) return '';
    
    const bom = dataView.getUint16(offset);
    const littleEndian = bom === 0xFFFE;
    
    let start = offset;
    if (bom === 0xFEFF || bom === 0xFFFE) {
      start += 2;
    }
    
    const chars: number[] = [];
    for (let i = start; i < offset + length; i += 2) {
      const char = dataView.getUint16(i, littleEndian);
      if (char === 0) break;
      chars.push(char);
    }
    
    return String.fromCharCode(...chars).trim();
  }

  /**
   * 读取 UTF-16BE 字符串
   */
  private static readUTF16BEString(dataView: DataView, offset: number, length: number): string {
    const chars: number[] = [];
    for (let i = offset; i < offset + length; i += 2) {
      const char = dataView.getUint16(i, false);
      if (char === 0) break;
      chars.push(char);
    }
    return String.fromCharCode(...chars).trim();
  }

  /**
   * 读取 UTF-8 字符串
   */
  private static readUTF8String(dataView: DataView, offset: number, length: number): string {
    const bytes: number[] = [];
    for (let i = 0; i < length; i++) {
      const byte = dataView.getUint8(offset + i);
      if (byte === 0) break;
      bytes.push(byte);
    }
    return ID3Parser.decodeUTF8(bytes).trim();
  }

  /**
   * 解码 UTF-8 字节数组
   */
  private static decodeUTF8(bytes: number[]): string {
    let result = '';
    let i = 0;
    
    while (i < bytes.length) {
      const byte1 = bytes[i];
      
      if (byte1 < 0x80) {
        result += String.fromCharCode(byte1);
        i++;
      } else if ((byte1 & 0xE0) === 0xC0) {
        const byte2 = bytes[i + 1] || 0;
        result += String.fromCharCode(((byte1 & 0x1F) << 6) | (byte2 & 0x3F));
        i += 2;
      } else if ((byte1 & 0xF0) === 0xE0) {
        const byte2 = bytes[i + 1] || 0;
        const byte3 = bytes[i + 2] || 0;
        result += String.fromCharCode(((byte1 & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F));
        i += 3;
      } else {
        i++;
      }
    }
    
    return result;
  }

  /**
   * 提取封面图片数据
   */
  private static extractCoverData(dataView: DataView, offset: number, length: number): ArrayBuffer | undefined {
    try {
      // 跳过文本编码字节
      let pos = offset + 1;
      
      // 跳过 MIME 类型（以 null 结尾）
      while (pos < offset + length && dataView.getUint8(pos) !== 0) {
        pos++;
      }
      pos++; // 跳过 null
      
      // 跳过图片类型字节
      pos++;
      
      // 跳过描述文本（以 null 结尾）
      while (pos < offset + length && dataView.getUint8(pos) !== 0) {
        pos++;
      }
      pos++; // 跳过 null
      
      // 剩余部分就是图片数据
      const imageLength = offset + length - pos;
      if (imageLength > 0) {
        return dataView.buffer.slice(pos, pos + imageLength);
      }
    } catch (err) {
      console.error('提取封面数据失败:', err);
    }
    return undefined;
  }

  /**
   * 估算音频时长（基于文件大小和比特率）
   */
  private static async estimateDuration(filePath: string): Promise<number> {
    try {
      const stat = fileIo.statSync(filePath);
      const fileSize = stat.size;
      
      // 尝试从文件头部读取比特率信息
      let bitrate = 128000; // 默认 128 kbps（bits per second）
      
      try {
        const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
        const headerBuffer = new ArrayBuffer(4);
        const headerView = new DataView(headerBuffer);
        
        // 读取前4个字节检查帧头
        fileIo.readSync(file.fd, headerBuffer, { offset: 0, length: 4 });
        
        // 检查是否是 ID3 标签，如果是则跳过
        const id3Tag = ID3Parser.readString(headerView, 0, 3);
        let dataOffset = 0;
        
        if (id3Tag === 'ID3') {
          // ID3v2 标签，读取标签大小
          const tagSize = ID3Parser.readSyncSafeInt(headerView, 6);
          dataOffset = 10 + tagSize; // ID3 头(10字节) + 标签大小
        }
        
        // 尝试找到第一个 MP3 帧头
        // 读取更多数据来查找帧头
        const searchBuffer = new ArrayBuffer(4096);
        fileIo.readSync(file.fd, searchBuffer, { offset: dataOffset, length: 4096 });
        const searchView = new DataView(searchBuffer);
        
        // 查找 MP3 帧同步字 (11个1: 0xFFE)
        for (let i = 0; i < 4092; i++) {
          const byte1 = searchView.getUint8(i);
          const byte2 = searchView.getUint8(i + 1);
          
          // 检查帧同步 (0xFFE)
          if (byte1 === 0xFF && (byte2 & 0xE0) === 0xE0) {
            // 找到帧头，解析比特率
            const byte3 = searchView.getUint8(i + 2);
            const bitrateIndex = (byte3 >> 4) & 0x0F;
            
            // MPEG 版本和层信息
            const mpegVersion = (byte2 >> 3) & 0x03;
            const layer = (byte2 >> 1) & 0x03;
            
            // 比特率表 (Layer III)
            const bitrateTable: number[] = [
              0, 32000, 40000, 48000, 56000, 64000, 80000, 96000,
              112000, 128000, 160000, 192000, 224000, 256000, 320000, 0
            ];
            
            if (bitrateIndex > 0 && bitrateIndex < 15) {
              bitrate = bitrateTable[bitrateIndex];
              console.info(`检测到比特率: ${bitrate / 1000} kbps`);
              break;
            }
          }
        }
        
        fileIo.closeSync(file);
      } catch (err) {
        console.warn('读取比特率失败，使用默认值:', err);
      }
      
      // 计算音频数据大小（减去 ID3 标签的估算大小）
      // 估算 ID3 标签大小为文件大小的 1% 到 10%
      const estimatedTagSize = Math.min(fileSize * 0.1, 100 * 1024); // 最多 100KB
      const audioDataSize = fileSize - estimatedTagSize;
      
      // 计算时长: (文件大小 - 标签大小) * 8 / 比特率
      const estimatedSeconds = (audioDataSize * 8) / bitrate;
      
      console.info(`文件大小: ${fileSize}, 估算音频大小: ${audioDataSize}, 比特率: ${bitrate}, 估算时长: ${estimatedSeconds}s`);
      
      return Math.floor(estimatedSeconds * 1000);
    } catch (err) {
      console.error('估算时长失败:', err);
      return 0;
    }
  }

  /**
   * 从文件路径创建 TrackInfo
   * @param filePath 文件路径
   * @returns TrackInfo 对象
   */
  static async createTrackFromFile(filePath: string): Promise<TrackInfo> {
    const id3Info = await ID3Parser.parseID3(filePath);
    
    // 从文件名提取标题（如果没有 ID3 标签）
    let title = id3Info.title;
    if (!title) {
      const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
      title = fileName.substring(0, fileName.lastIndexOf('.'));
    }
    
    const options: TrackInfoOptions = {
      title: title || '未知歌曲',
      artist: id3Info.artist || '未知歌手',
      album: id3Info.album || '未知专辑',
      duration: id3Info.duration || 0,
      filePath: filePath,
      addedAt: Date.now()
    };
    return new TrackInfo(options);
  }
}
