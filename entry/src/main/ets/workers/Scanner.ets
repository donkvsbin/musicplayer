/**
 * 文件扫描器 Worker
 * 在独立线程中扫描音频文件并解析元数据
 */

import { worker, MessageEvents } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { ID3Parser } from '../utils/ID3Parser';
import { TrackInfo } from '../models/TrackInfo';
import { AUDIO_EXTENSIONS, SCAN_BATCH_SIZE } from '../constants/AppConstants';

/**
 * 扫描进度信息
 */
export interface ScanProgress {
  type: 'progress' | 'completed' | 'error';
  scannedCount: number;
  foundCount: number;
  insertedCount: number;
  currentPath?: string;
  error?: string;
}

/**
 * 扫描选项
 */
export interface ScanOptions {
  directories: string[];
  recursive: boolean;
}

// Worker 线程上下文
const workerPort = worker.workerPort;

/**
 * 检查文件是否是音频文件
 */
function isAudioFile(fileName: string): boolean {
  const lowerName = fileName.toLowerCase();
  return AUDIO_EXTENSIONS.some(ext => lowerName.endsWith(ext));
}

/**
 * 递归扫描目录
 */
async function scanDirectory(
  dirPath: string, 
  recursive: boolean, 
  audioFiles: string[]
): Promise<void> {
  try {
    // 使用 listFile 获取目录内容   
    const files: string[] = await fileIo.listFile(dirPath);
    
    for (const file of files) {
      const fullPath = dirPath + '/' + file;
      
      try {
        const stat = fileIo.statSync(fullPath);
        
        if (stat.isDirectory() && recursive) {
          // 递归扫描子目录
          await scanDirectory(fullPath, recursive, audioFiles);
        } else if (stat.isFile() && isAudioFile(file)) {
          // 找到音频文件
          audioFiles.push(fullPath);
        }
      } catch (statErr) {
        // 忽略无法访问的文件
        console.warn(`无法访问文件: ${fullPath}`);
      }
    }
  } catch (err) {
    console.error(`扫描目录失败: ${dirPath}`, err);
  }
}

/**
 * 解析音频文件元数据
 */
async function parseAudioFiles(filePaths: string[]): Promise<TrackInfo[]> {
  const tracks: TrackInfo[] = [];
  
  for (const filePath of filePaths) {
    try {
      const track = await ID3Parser.createTrackFromFile(filePath);
      tracks.push(track);
    } catch (err) {
      console.error(`解析文件失败: ${filePath}`, err);
    }
  }
  
  return tracks;
}

/**
 * 发送进度消息到主线程
 */
function sendProgress(progress: ScanProgress): void {
  try {
    workerPort.postMessage(progress);
  } catch (err) {
    console.error('发送进度消息失败:', err);
  }
}

/**
 * 执行扫描任务
 */
async function performScan(options: ScanOptions): Promise<void> {
  const startTime = Date.now();
  const audioFiles: string[] = [];
  
  console.info('开始扫描音频文件...');
  
  try {
    // 第一阶段：扫描目录收集音频文件
    for (const dir of options.directories) {
      try {
        const stat = fileIo.statSync(dir);
        if (stat.isDirectory()) {
          await scanDirectory(dir, options.recursive, audioFiles);
        }
      } catch (err) {
        console.error(`无法访问目录: ${dir}`, err);
      }
    }
    
    console.info(`扫描完成，找到 ${audioFiles.length} 个音频文件`);
    
    // 第二阶段：批量解析元数据
    const totalFiles = audioFiles.length;
    let parsedCount = 0;
    let insertedCount = 0;
    
    // 分批处理
    for (let i = 0; i < totalFiles; i += SCAN_BATCH_SIZE) {
      const batch = audioFiles.slice(i, i + SCAN_BATCH_SIZE);
      
      // 解析当前批次
      const tracks = await parseAudioFiles(batch);
      parsedCount += tracks.length;
      
      // 发送进度更新
      sendProgress({
        type: 'progress',
        scannedCount: Math.min(i + SCAN_BATCH_SIZE, totalFiles),
        foundCount: totalFiles,
        insertedCount: parsedCount,
        currentPath: batch[batch.length - 1]
      });
      
      // 发送解析后的歌曲数据到主线程
      workerPort.postMessage({
        type: 'batch',
        tracks: tracks
      });
    }
    
    const duration = Date.now() - startTime;
    console.info(`扫描任务完成，耗时: ${duration}ms`);
    
    // 发送完成消息
    sendProgress({
      type: 'completed',
      scannedCount: totalFiles,
      foundCount: totalFiles,
      insertedCount: parsedCount
    });
    
  } catch (err) {
    console.error('扫描任务失败:', err);
    sendProgress({
      type: 'error',
      scannedCount: 0,
      foundCount: 0,
      insertedCount: 0,
      error: err instanceof Error ? err.message : '未知错误'
    });
  }
}

// 扫描消息类型
interface ScanMessage {
  type: string;
  options?: ScanOptions;
}

// 监听主线程消息
workerPort.onmessage = (e: MessageEvents): void => {
  const message: ScanMessage = e.data as ScanMessage;
  
  if (message.type === 'start') {
    if (!message.options) {
      console.error('扫描任务缺少 options 参数');
      return;
    }
    performScan(message.options);
  } else if (message.type === 'stop') {
    // 停止扫描（当前实现会完成当前批次后停止）
    console.info('收到停止扫描请求');
  }
};

console.info('Scanner Worker 已启动');
