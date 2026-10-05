import { createHash } from 'node:crypto'
import { createReadStream } from 'node:fs'
import { open, stat } from 'node:fs/promises'
import { AUDIO_UNSUPPORTED, MAX_SILENCE_REGIONS, type AudioAnalysisParameters, type AudioAnalysisPayload } from '../../artifacts/audio-analysis.js'

export const ANALYZER = { name: 'artist-os-wav-basic', version: '2.0.0' } as const

export class AnalysisError extends Error {
  constructor(
    readonly code: 'UNSUPPORTED_FORMAT' | 'CORRUPT_FILE' | 'FILE_UNREADABLE' | 'HASH_MISMATCH' | 'EMPTY_AUDIO',
    message: string,
    readonly retryable = false,
  ) {
    super(message)
    this.name = 'AnalysisError'
  }
}

interface WavFormat {
  encoding: AudioAnalysisPayload['format']['encoding']
  sampleRate: number
  channels: number
  bitsPerSample: number
  blockAlign: number
  dataOffset: number
  dataBytes: number
}

const db = (linear: number) => (linear > 0 ? 20 * Math.log10(linear) : null)

/** Reads the RIFF/WAVE header from the first bytes only (bounded memory). */
async function readHeader(path: string, size: number): Promise<WavFormat> {
  const fh = await open(path, 'r')
  try {
    const head = Buffer.alloc(Math.min(size, 1 << 20))
    const { bytesRead } = await fh.read(head, 0, head.length, 0)
    const b = head.subarray(0, bytesRead)
    if (b.length < 12 || b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') {
      throw new AnalysisError('UNSUPPORTED_FORMAT', 'not a RIFF/WAVE file (only WAV is supported; no transcoding is attempted)')
    }
    let pos = 12
    let fmt: Omit<WavFormat, 'dataOffset' | 'dataBytes'> | undefined
    while (pos + 8 <= b.length) {
      const id = b.toString('ascii', pos, pos + 4)
      const len = b.readUInt32LE(pos + 4)
      const body = pos + 8
      if (id === 'fmt ') {
        if (body + 16 > b.length) throw new AnalysisError('CORRUPT_FILE', 'truncated fmt chunk')
        let tag = b.readUInt16LE(body)
        const channels = b.readUInt16LE(body + 2)
        const sampleRate = b.readUInt32LE(body + 4)
        const blockAlign = b.readUInt16LE(body + 12)
        const bits = b.readUInt16LE(body + 14)
        if (tag === 0xfffe && len >= 40 && body + 26 <= b.length) tag = b.readUInt16LE(body + 24) // WAVE_FORMAT_EXTENSIBLE sub-format
        let encoding: WavFormat['encoding'] | undefined
        if (tag === 1 && bits === 16) encoding = 'pcm_s16le'
        else if (tag === 1 && bits === 24) encoding = 'pcm_s24le'
        else if (tag === 1 && bits === 32) encoding = 'pcm_s32le'
        else if (tag === 3 && bits === 32) encoding = 'float32'
        if (!encoding) throw new AnalysisError('UNSUPPORTED_FORMAT', `unsupported WAV encoding (tag ${tag}, ${bits} bits)`)
        if (channels < 1 || sampleRate < 1 || blockAlign !== channels * (bits / 8)) throw new AnalysisError('CORRUPT_FILE', 'inconsistent fmt chunk')
        fmt = { encoding, sampleRate, channels, bitsPerSample: bits, blockAlign }
      } else if (id === 'data') {
        if (!fmt) throw new AnalysisError('CORRUPT_FILE', 'data chunk before fmt chunk')
        // A streamed WAV may declare 0 / 0xFFFFFFFF; clamp to what is actually on disk.
        const avail = size - body
        const streamed = len === 0 || len === 0xffffffff
        // A declared size larger than the bytes on disk means the file is truncated: refuse rather than analyze a part.
        if (!streamed && len > avail) throw new AnalysisError('CORRUPT_FILE', 'file ends before the declared audio data (truncated)')
        const declared = streamed ? avail : len
        return { ...fmt, dataOffset: body, dataBytes: Math.min(declared, avail) }
      }
      pos = body + len + (len % 2)
    }
    throw new AnalysisError('CORRUPT_FILE', 'no data chunk found within the header region')
  } finally {
    await fh.close()
  }
}

/**
 * Streams the file once: SHA-256 of ALL bytes plus the measurements over the data chunk.
 * Memory is bounded (one read buffer) regardless of file size. Pure local I/O: no network, no model.
 */
export async function analyzeWavFile(path: string, params: AudioAnalysisParameters, opts: { expectedHash?: string; assetRef?: string; onProgress?: (fraction: number) => void } = {}): Promise<AudioAnalysisPayload> {
  let size: number
  try {
    size = (await stat(path)).size
  } catch {
    throw new AnalysisError('FILE_UNREADABLE', 'input asset is not readable on this runner', true)
  }
  const fmt = await readHeader(path, size)
  const bytesPerSample = fmt.bitsPerSample / 8
  const frames = Math.floor(fmt.dataBytes / fmt.blockAlign)
  if (frames === 0) throw new AnalysisError('EMPTY_AUDIO', 'the data chunk contains no audio frames')
  const dataEnd = fmt.dataOffset + frames * fmt.blockAlign

  const silenceAmp = 10 ** (params.silenceThresholdDb / 20)
  // Positive full scale of an n-bit PCM sample is (2^(n-1)-1)/2^(n-1), i.e. just below 1.0; floats clip at >= 1.0.
  const clipAt = fmt.encoding === 'float32' ? 1 : 1 - 1 / 2 ** (fmt.bitsPerSample - 1)
  const hash = createHash('sha256')
  let peak = 0
  let sumSq = 0
  let clipped = 0
  let silentFrames = 0
  let seenSound = false
  let runStart = -1 // frame index where the current silent run began
  const regions: { startSec: number; endSec: number }[] = []
  let regionCount = 0
  const minRunFrames = Math.max(1, Math.round(params.minSilenceSec * fmt.sampleRate))
  const closeRun = (endFrame: number) => {
    if (runStart >= 0 && endFrame - runStart >= minRunFrames) {
      regionCount++
      if (regions.length < MAX_SILENCE_REGIONS) regions.push({ startSec: runStart / fmt.sampleRate, endSec: endFrame / fmt.sampleRate })
    }
    runStart = -1
  }
  let frameIndex = 0
  let consumed = 0 // bytes of the data region processed
  let carry = Buffer.alloc(0)

  const decode = (buf: Buffer, off: number): number => {
    switch (fmt.encoding) {
      case 'pcm_s16le': return buf.readInt16LE(off) / 32768
      case 'pcm_s24le': return buf.readIntLE(off, 3) / 8388608
      case 'pcm_s32le': return buf.readInt32LE(off) / 2147483648
      case 'float32': return buf.readFloatLE(off)
    }
  }

  const stream = createReadStream(path, { highWaterMark: 1 << 20 })
  let offset = 0
  try {
    for await (const chunk of stream as AsyncIterable<Buffer>) {
      hash.update(chunk)
      // Slice this chunk's overlap with the data region.
      const start = Math.max(fmt.dataOffset - offset, 0)
      const end = Math.min(dataEnd - offset, chunk.length)
      offset += chunk.length
      if (end <= start) continue
      let buf = chunk.subarray(start, end)
      if (carry.length) buf = Buffer.concat([carry, buf])
      const usable = buf.length - (buf.length % fmt.blockAlign)
      for (let o = 0; o < usable; o += fmt.blockAlign) {
        let frameMax = 0
        for (let c = 0; c < fmt.channels; c++) {
          const v = decode(buf, o + c * bytesPerSample)
          const a = Math.abs(v)
          if (a > frameMax) frameMax = a
          if (a >= clipAt) clipped++
          sumSq += v * v
        }
        if (frameMax > peak) peak = frameMax
        if (frameMax < silenceAmp) {
          silentFrames++
          if (runStart < 0) runStart = frameIndex
        } else {
          seenSound = true
          closeRun(frameIndex)
        }
        frameIndex++
      }
      carry = Buffer.from(buf.subarray(usable))
      consumed += usable
      opts.onProgress?.(Math.min(consumed / (frames * fmt.blockAlign), 1))
    }
  } catch (e) {
    if (e instanceof AnalysisError) throw e
    throw new AnalysisError('FILE_UNREADABLE', 'read error while analyzing', true)
  }
  if (frameIndex !== frames) throw new AnalysisError('CORRUPT_FILE', 'file ended before the declared audio data (truncated)')

  const contentHash = `sha256:${hash.digest('hex')}`
  if (opts.expectedHash && opts.expectedHash !== contentHash) {
    throw new AnalysisError('HASH_MISMATCH', 'file content does not match the AssetRef contentHash; refusing to report analysis of different audio')
  }
  closeRun(frames)
  const totalSamples = frames * fmt.channels
  const allSilent = !seenSound
  const peakDb = db(peak)
  const rmsDb = db(Math.sqrt(sumSq / totalSamples))
  return {
    sourceAssetRef: { assetRef: opts.assetRef ?? 'unspecified', contentHash },
    contentHash,
    analyzer: ANALYZER.name,
    analyzerVersion: ANALYZER.version,
    format: { container: 'wav', encoding: fmt.encoding, sampleRate: fmt.sampleRate, channels: fmt.channels, bitsPerSample: fmt.bitsPerSample },
    sizeBytes: size,
    frames,
    durationSec: frames / fmt.sampleRate,
    signal: allSilent && peakDb === null ? 'digital_silence' : 'audible',
    peakDb,
    rmsDb,
    clipCount: clipped,
    silenceRegions: {
      thresholdDb: params.silenceThresholdDb,
      minSilenceSec: params.minSilenceSec,
      regions,
      truncated: regionCount > regions.length,
      totalSilentSec: silentFrames / fmt.sampleRate,
    },
    unsupported: { ...AUDIO_UNSUPPORTED },
  }
}
