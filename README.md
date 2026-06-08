# TakeLayer 統合設計書 v1.2

DAWで音を作る人のための、撮りっぱなし演奏動画アセンブラー

## 0. 一文定義

TakeLayerは、DAWで作った完成WAVと、撮りっぱなしの演奏動画それぞれに「曲開始基準点」を設定し、同じプロジェクト時間軸へ安全に並べ、手動補正と自動候補化で整え、DAW音質の演奏動画として書き出すアプリ。

もっと短く言うなら、

スマホで撮った演奏を、DAW完成音源つきの動画に整える。

## 1. コンセプト

### 1-1. 何を作るか

TakeLayerは、音楽家がDAWで普通に録音・ミックスしながら、スマホで撮りっぱなしにした演奏動画を、あとから完成WAV基準で同期・整理・書き出しするアプリ。

DAWを置き換えない。  
動画編集アプリになりすぎない。  
演奏動画に必要な「同期・整理・分割・完成WAV差し込み」に集中する。

### 1-2. 何を解決するか

音楽家が演奏動画を作るときの面倒は、主にここにある。

- 録画する
- DAWで音を仕上げる
- 動画を読み込む
- 曲頭を探す
- WAVと合わせる
- 余白を切る
- 複数動画を並べる
- ズレを確認する
- 書き出す

TakeLayerはこのうち、動画側の整理・同期・書き出しを肩代わりする。

### 1-3. アプリの哲学

音はDAWで磨く。  
映像はTakeLayerが整える。  
録音の流れは邪魔しない。

このアプリは、演奏中に賢そうに振る舞うアプリではない。  
演奏中は静かに記録し、終わったあとに、素材を時間軸へきれいに並べる。

## 2. コア思想

### 2-1. DAW非連携

DAWとは直接連携しない。

Logic、Cubase、Studio One、Ableton、Pro Toolsなど、DAWごとのAPI連携に入ると一気に複雑になる。  
TakeLayerはDAWとつながるのではなく、完成WAVという標準ファイルを受け取る。

つまり、

- DAW → 完成WAVを書き出す
- TakeLayer → 完成WAVを基準に動画を整える

という関係にする。

### 2-2. メトロノーム時間軸ではなく「曲開始アンカー付きプロジェクト時間軸」

当初の「メトロノーム時間軸カメラ」という考え方は良い。  
ただし、DAW非連携の場合、アプリはDAWの1小節目1拍目を自動では知れない。

そこで設計の中心をこう定義し直す。

```text
Project timeline 0:00
= 曲の開始
= 完成WAVの音楽開始点
= 各動画を並べるための共通原点
```

各動画は、

```text
raw動画内の何秒地点が Project timeline 0:00 なのか
```

を持つ。

これが `songStartRawSec`。

完成WAV側も、

```text
WAV内の何秒地点が Project timeline 0:00 なのか
```

を持つ。

これが `songStartAudioSec`。

この2つがTakeLayerの心臓。

### 2-3. 完成WAVをReference Performance Anchorにする

TakeLayerにおける時間の正本は、基本的に完成WAV。

完成WAVは、DAWで整えた最終音源であり、動画に差し込む本番音声。  
各動画は、最終的にこの完成WAVへ合わせる。

ただし、完成WAVの先頭が必ず曲開始とは限らない。  
カウントイン、冒頭無音、書き出し余白がある可能性がある。  
だからWAV側にも `songStartAudioSec` を持つ。

### 2-4. 曲中の無音は切らない

TakeLayerは、音がないからといって切らない。

曲中には、

- 休符
- ブレイク
- ボーカル待ち
- ギター待ち
- ドラムだけになる場所
- サビ前のタメ

がある。

だから自動トリムは「無音カット」ではなく、曲尺ウィンドウ探索にする。

悪い考え方：

```text
音がある → 残す
音がない → 切る
```

正しい考え方：

```text
この曲尺ぶんの窓は、本テイクとして自然か？
一度採用した窓の内側は切らない
```

### 2-5. 完全自動ではなく「候補提示 + 手動確認」

TakeLayerは裁判官ではない。  
助手である。

アプリが勝手に「これが正解」と決めるより、

```text
これが本テイク候補です
理由はこうです
ズレはこれくらいです
ここを直せます
```

と出して、人間が気持ちよく確定できる方が強い。

## 3. 主要用語

### Project timeline

曲全体の共通時間軸。  
0:00 は曲開始。

### songStartRawSec

raw動画内で、Project timeline 0:00 に対応する秒数。

例：

```text
raw動画 48.32秒 = 曲タイムライン 0:00
```

### songStartAudioSec

完成WAV内で、Project timeline 0:00 に対応する秒数。

例：

```text
WAV 2.00秒 = 曲タイムライン 0:00
```

### SyncAnchor

動画側の任意の基準点。

例：

- 曲開始
- 曲終わり
- サビ頭
- 同期クリック
- 手動マーカー

### MasterAudioAnchor

完成WAV側の基準点。

例：

- WAV内の曲開始
- WAV内の同期クリック
- WAV内のサビ頭

### selectedRawStartSec / selectedRawEndSec

raw動画から実際に使う範囲。  
これは曲開始とは別。

### firstSoundRawSec

そのパートが最初に鳴り始めた位置。  
曲開始とは別。

例：ボーカルが40秒後に入る曲では、

```text
songStartRawSec = 10.0
firstSoundRawSec = 50.0
```

となる可能性がある。

## 4. MVP方針

### 4-1. 最初に作るべきもの

いきなり「録画 + 自動トリム + 自動同期 + 4分割 + Shorts」まで作らない。

最初は Import-first Export PoC から始める。

つまり、カメラ機能すら最初は不要。

#### Phase 0.5A：Import-first Export PoC

目的は、TakeLayerの骨を検証すること。

必須機能

1. 動画をインポート
2. 完成WAVをインポート
3. 動画側の曲開始位置 `songStartRawSec` を手動指定
4. WAV側の曲開始位置 `songStartAudioSec` を手動指定
5. 曲尺ぶんを切り出す
6. カメラ音声をミュート
7. 完成WAVを差し込む
8. 1画面MP4で書き出す
9. 可能なら2分割/4分割も検証

このPoCが通れば、アプリの根幹は成立する。

### 4-2. MVP-α

PoCの次は、1本動画 + 完成WAV差し替え。

MVP-αの価値

スマホで撮った演奏動画を、DAW音質の動画に変える。

MVP-αでやること

- アプリ内録画
- 動画インポート
- 完成WAV読み込み
- 動画側曲開始マーカー
- WAV側曲開始マーカー
- 手動トリム
- 自動同期補助
- 手動オフセット補正
- カメラ音声ミュート
- 完成WAV差し込み
- 1画面MP4書き出し
- 容量表示
- Zenモード

MVP-αでやらないこと

- 完全自動テイク判定
- 複雑な曲中無音判定
- 複数パートの自動レイアウト
- セクション別切り替え
- AIクロップ
- 歌詞テロップ
- Android対応
- Mac Companion
- 自動ドリフト補正

### 4-3. MVP-β

MVP-αの後に複数パート対応へ進む。

MVP-βでやること

- 複数Take
- Part管理
- 2分割/4分割
- 各動画を完成WAV基準で配置
- パート別オフセット補正
- タイムライン表示
- ズレ表示
- カメラ音声レイヤー保持

## 5. 技術方針

### 5-1. 基本スタック

iOS MVPは、Swift / SwiftUI + AVFoundation + Accelerate/vDSP + SwiftData を基本にする。

理由は、TakeLayerの中核が録画・音声解析・動画合成・WAV差し替え・書き出しだから。  
AppleのAVFoundationは、時間ベースのオーディオビジュアルメディアの再生・作成・編集などを扱うフレームワークとして提供されている。AVMutableCompositionは複数メディアのトラックを挿入・削除・スケールするための土台になり、SwiftDataはSwiftコードでモデル層を定義・永続化するためのApple公式フレームワークとして使える。(Apple Developer)

### 5-2. 音声解析

音声解析は、Accelerate/vDSPを使う。  
vDSPにはFFTなどのDSP処理が用意されているため、将来的な相関計算やGCC-PHAT系の検証に向いている。(Apple Developer)

MVPでは最初から高度な相関をやりすぎない。

優先順は、

1. 波形/RMS表示
2. 手動マーカー
3. オフセット補正
4. 同期クリック検出
5. 完成WAV × カメラ音声の簡易照合
6. GCC-PHAT / FFT系照合
7. 終点ズレ検出
8. ドリフト補正

### 5-3. FFmpegKitは中核依存にしない

FFmpegKitは公式リポジトリ上で retired と明記され、今後のリリースなし・既存バイナリ削除予定も示されている。新規モバイルアプリの長期中核依存にはしない。(GitHub)

使うとしても、

- Mac Companion
- サーバー処理
- 短期PoC
- 緊急フォールバック

程度に留める。

### 5-4. Androidは後フェーズ

Android版は初期から作らない。  
将来的にはMedia3 Transformerが候補。Android公式ドキュメントでは、Media3 Transformerはトランスコード、トリム、クロップ、エフェクトなどの編集APIとして説明されており、Composition APIやmulti-asset editingも用意されている。(Android Developers)

## 6. 初期対応制限

MVPでは、あえて制限を強くする。

- 対象：iOS
- 最大パート：4
- 出力：1080p / 30fps
- 色：SDR優先
- 動画：H.264 / AAC
- WAV：PCM 44.1kHz / 48kHz対応
- 最大尺：6〜8分程度
- クラウド：なし
- 4K：後回し
- HDR：警告またはSDR変換方針
- AIクロップ：なし
- 歌詞テロップ：なし

制限は弱さではなく、信頼性のため。

## 7. データ構造

以下はTypeScript風の概念モデル。  
実装時はSwiftDataモデルへ変換する。

### Project

```ts
type Project = {
  id: string
  title: string

  timeline: ProjectTimeline

  parts: Part[]
  takes: Take[]
  masterAudio?: MasterAudio

  layouts: LayoutPreset[]

  storagePolicy: StoragePolicy

  createdAt: string
  updatedAt: string
  schemaVersion: number
}
```

### ProjectTimeline

```ts
type ProjectTimeline = {
  // Project timeline 0:00 = 曲開始
  durationSec: number

  bpm?: number

  timeSignature?: {
    numerator: number
    denominator: number
  }

  countInBars?: number

  zeroPointLabel: 'song_start'

  sections: Section[]

  // 将来のテンポチェンジ対応
  tempoMap?: TempoSegment[]
}
```

### Section

内部的には小節より拍基準の方が強い。

```ts
type Section = {
  id: string
  name: string
  startBeat: number
  endBeat: number
}
```

### MasterAudio

```ts
type MasterAudio = {
  id: string
  projectId: string
  fileUri: string

  durationSec: number
  sampleRate: number
  bitDepth?: number

  // WAV内で Project timeline 0:00 に対応する位置
  songStartAudioSec: number

  anchors: MasterAudioAnchor[]

  importedAt: Date
}
```

### MasterAudioAnchor

```ts
type MasterAudioAnchor = {
  id: string
  masterAudioId: string

  audioSec: number
  timelineSec: number

  kind:
    | 'manual'
    | 'sync_cue'
    | 'detected_silence'
    | 'imported_marker'

  confidence: number
}
```

### Part

```ts
type Part = {
  id: string
  projectId: string
  name: string

  type:
    | 'drums'
    | 'bass'
    | 'guitar'
    | 'vocal'
    | 'chorus'
    | 'keys'
    | 'other'

  color?: string
  order: number
}
```

### Take

```ts
type Take = {
  id: string
  projectId: string
  partId: string

  media: MediaInfo

  // raw動画内で Project timeline 0:00 に対応する位置
  songStartRawSec?: number

  // raw動画から実際に使用する範囲
  selectedRawStartSec?: number
  selectedRawEndSec?: number

  // このパートが最初に鳴り始めた位置。曲開始とは別
  firstSoundRawSec?: number

  anchors: SyncAnchor[]

  recordedAt: Date

  offsetMs: number
  driftPpm?: number

  userRating?: number
  userNote?: string

  analysis?: AnalysisResult

  confidence: number
  status: 'raw' | 'analyzed' | 'selected' | 'rejected'
  userAdjusted: boolean
}
```

### SyncAnchor

```ts
type SyncAnchor = {
  id: string
  takeId: string

  rawSec: number
  timelineSec: number

  kind:
    | 'manual'
    | 'audio_match'
    | 'sync_cue'
    | 'app_count_in'
    | 'imported_marker'

  confidence: number
  locked: boolean
}
```

### MediaInfo

```ts
type MediaInfo = {
  uri: string

  durationSec: number
  width: number
  height: number

  fps?: number

  hasAudio: boolean
  audioSampleRate?: number

  orientation?: 'portrait' | 'landscape'

  codec?: string
  colorSpace?: 'sdr' | 'hdr' | 'unknown'

  fileSizeBytes?: number
}
```

### AnalysisResult

```ts
type AnalysisResult = {
  takeId: string

  candidates: TakeCandidate[]

  waveformAssetId?: string

  syncResultIds: string[]

  warnings: string[]
}
```

### TakeCandidate

```ts
type TakeCandidate = {
  id: string
  takeId: string

  startSec: number
  endSec: number
  durationSec: number

  confidence: number

  reasons: {
    durationMatch?: number
    audioActivity?: number
    syncConfidence?: number
    startNaturalness?: number
    endNaturalness?: number
  }

  warning?: string
}
```

### SyncResult

```ts
type SyncResult = {
  id: string
  takeId: string
  masterAudioId: string

  method:
    | 'manual'
    | 'sync_click'
    | 'audio_match'
    | 'gcc_phat'
    | 'imported_marker'

  offsetMs: number
  confidence: number

  driftMsAtEnd?: number
  driftPpm?: number

  needsManualReview: boolean

  createdAt: Date
}
```

### OutputAudioConfig

```ts
type OutputAudioConfig = {
  primary: 'master_audio' | 'camera_audio'

  masterAudioVolume: number
  cameraAudioVolume: number

  // 後フェーズ用。サビだけカメラ音声を薄く混ぜるなど。
  cameraAudioMoments?: {
    startSec: number
    endSec: number
    volume: number
  }[]
}
```

### LayoutPreset

```ts
type LayoutPreset = {
  id: string
  projectId: string

  name: string

  type:
    | 'single'
    | 'grid_2x1'
    | 'grid_2x2'
    | 'vertical_3'
    | 'custom'

  aspectRatio: '16:9' | '9:16' | '1:1'
  resolution: '720p' | '1080p' | '4K'

  placements: PartPlacement[]
}
```

### PartPlacement

```ts
type PartPlacement = {
  partId?: string
  takeId: string

  position: { x: number; y: number }
  size: { width: number; height: number }

  cropRect?: {
    x: number
    y: number
    width: number
    height: number
  }
}
```

### StoragePolicy

```ts
type StoragePolicy = {
  defaultResolution: '720p' | '1080p'
  defaultFps: 30

  keepOriginalAfterTrim: boolean
  autoSuggestDeleteRejectedTakes: boolean

  warnWhenFreeSpaceBelowGB: number
}
```

## 8. 同期設計

### 8-1. 基本モデル

すべての素材は Project timeline に配置される。

```text
Project timeline 0:00 = 曲開始
```

動画は、

```text
songStartRawSec → timeline 0:00
```

で配置される。

WAVは、

```text
songStartAudioSec → timeline 0:00
```

で配置される。

### 8-2. 配置例

```text
Project timeline:
0:00        曲開始
3:42        曲終了

Master WAV:
songStartAudioSec = 0.00

Guitar Take:
songStartRawSec = 48.32
selectedRawStartSec = 48.32
selectedRawEndSec = 270.32

Vocal Take:
songStartRawSec = 12.00
firstSoundRawSec = 52.00
selectedRawStartSec = 12.00
selectedRawEndSec = 234.00
```

ボーカルが40秒後に歌い始めても、動画は曲頭から配置できる。  
これが重要。

### 8-3. 自動同期の役割

自動同期は `songStartRawSec` や `offsetMs` を推定する補助。  
失敗しても手動で直せる。

同期の優先順位：

1. 手動アンカー
2. 同期クリック / Sync Cue
3. 完成WAV × カメラ音声の照合
4. BPM / 小節グリッド
5. 目視・手動オフセット

### 8-4. ドリフト

MVPでは自動補正しない。  
ただし、検出だけは将来入れる。

```text
曲頭ズレ：+8ms
曲終わりズレ：+46ms
終点差分：38ms
```

このように表示できると安心感が出る。

## 9. トリム設計

### 9-1. 手動トリムを先に作る

自動トリムより先に、手動トリムUIを作る。

理由：

- 自動判定の正解データを作れる
- 自動が外れても救済できる
- ユーザーの安心感が高い

### 9-2. 曲尺ウィンドウ探索

自動候補化は、無音検出ではなく「曲尺に合う窓」を探す。

```text
完成WAV尺 = 3:42
raw動画内のどこから3:42を切り出すと自然か？
```

### 9-3. 採用後の区間内は切らない

```text
[待機] [本テイク区間] [終了後余白]
  切る       残す         切る
```

本テイク区間内の無音・休符・ブレイクは残す。

## 10. UI/UX設計

### 10-1. ホーム

- プロジェクト一覧
- 新規プロジェクト
- 最近の書き出し
- プロジェクト容量表示

### 10-2. プロジェクト作成

MVPでは入力を少なくする。

必須：

- 曲名
- 完成WAV
- 動画

任意：

- BPM
- 拍子
- パート名
- セクション

### 10-3. Import画面

- 動画を追加
- WAVを追加
- 動画の情報表示
- WAV情報表示
- SDR/HDR警告
- FPS/解像度表示

### 10-4. 曲開始マーカー画面

ここが最重要UI。

動画側：

```text
この動画のどこが曲開始ですか？
```

WAV側：

```text
このWAVのどこが曲開始ですか？
```

操作：

- 波形を見ながらマーカーを置く
- 動画を見ながらマーカーを置く
- ±1ms
- ±10ms
- ±1フレーム
- プレビュー
- A/B確認

### 10-5. 手動トリム画面

- `selectedRawStartSec`
- `selectedRawEndSec`
- 波形
- サムネイル
- 曲尺との差分
- 採用ボタン

### 10-6. 録画画面

MVP録画画面は最小。

- 3秒カウントダウン
- 赤い録画枠
- 経過時間
- 残り容量
- 停止ボタン
- 数秒後にZenモード

### 10-7. Zenモード

録画中は集中を邪魔しない。

```text
🔴 Recording
12:34
容量 OK
バッテリー OK
```

画面は暗め。  
派手な波形や小節表示は出しすぎない。

### 10-8. 解析結果画面

```text
本テイク候補を見つけました

候補A
00:12 - 00:37
25秒
短すぎるため非推奨

候補B
00:48 - 04:30
3分42秒
曲尺と一致
前後に余白あり
信頼度 86%

候補C
04:35 - 04:55
20秒
終了後の確認音声の可能性
```

理由を表示する。  
ブラックボックスにしない。

## 11. 書き出し設計

### 11-1. MVP書き出し

MVP-α：

- 1画面
- 完成WAV差し込み
- カメラ音声ミュート
- 1080p
- 30fps
- MP4
- H.264/AAC

### 11-2. MVP-β書き出し

- 2分割
- 4分割
- 縦型3段
- パート名表示
- 1080p / 30fps

### 11-3. カメラ音声レイヤー

MVPではミュート。  
ただし保持する。

後フェーズでは、

- Before/After
- 制作過程
- サビだけ生音
- チュートリアル

などに使える。

## 12. ストレージ/熱/安定性

### 12-1. MVPから必要

- 録画前の空き容量チェック
- 録画中の残り容量表示
- プロジェクト容量表示
- 書き出し後の素材整理提案
- 元動画削除は必ずユーザー確認
- デフォルト1080p/30fps
- 4Kは後回し

### 12-2. 非破壊編集

基本は非破壊。

raw動画はすぐ消さない。  
どこを使うかはメタデータで持つ。

削除は書き出し後に、

```text
未採用テイクを削除しますか？
```

と確認する。

## 13. フェーズ設計

### Phase 0：設計固定

- 一文定義
- コア思想
- データ構造
- 技術方針
- MVP制約
- UI方針
- テストケース

### Phase 0.5A：Import-first Export PoC

- 動画インポート
- 完成WAVインポート
- `songStartRawSec`指定
- `songStartAudioSec`指定
- 手動トリム
- 1画面書き出し
- 可能なら2分割/4分割

### Phase 0.5B：Recording PoC

- アプリ内録画
- Zenモード
- カメラ音声抽出
- 完成WAVとの同期補助
- 手動アンカー
- 終点ズレ確認

### Phase 1：MVP-α

- 1本動画 + 完成WAV差し替え
- 動画インポート/録画
- 手動曲開始マーカー
- 手動トリム
- 手動オフセット
- 1画面書き出し
- ストレージ管理

### Phase 2：MVP-β

- 複数パート
- 2分割/4分割
- 各TakeをProject timelineへ配置
- タイムライン表示
- パート別オフセット補正

### Phase 3：自動候補化

- 曲尺ウィンドウ探索
- 候補提示
- 理由表示
- ユーザー評価
- Undo

### Phase 4：同期補助強化

- カメラ音声 × 完成WAV照合
- 同期クリック
- Sync Guide WAV
- 終点ズレ検出
- ドリフト警告

### Phase 5：演出

- 制作過程風
- `recordedAt`順にパート登場
- セクション別レイアウト
- Shorts切り出し
- カメラ音声瞬間ミックス

### Phase 6：Pro拡張

- Strict Sync / Natural Sync
- Reference Map
- MIDIテンポマップ読み込み
- Mac Companion
- 4K
- 高度なプロキシ編集

## 14. 将来機能

### Sync Guide WAV

DAW非連携のまま精度を上げる機能。

TakeLayerが、

```text
TakeLayer Sync Guide.wav
```

を生成する。

内容：

- カウントイン
- 同期ビープ
- 必要ならクリック

ユーザーはDAWに読み込む。  
DAW連携ではなく、ただのWAVファイルとして扱う。

### Strict Sync / Natural Sync

将来、同期モードを分ける。

Strict Sync：

```text
正確に揃える
```

Natural Sync：

```text
演奏の人間味を残しながら整える
```

MVPには入れない。  
思想として保持。

### Mac Companion

将来のPro機能。

- 4K書き出し
- 長尺
- 重い解析
- 多パート
- 大量素材管理

iPhoneは撮影助手。  
Macは編集工房。

## 15. テストケース

最初から以下を用意する。

1. 曲頭から全員鳴る
2. ボーカルが40秒後に入る
3. ギターがサビまで入らない
4. 8秒ブレイクがある
5. 20秒失敗テイク後に本テイク
6. 本テイク後に会話
7. カメラ音声がほぼ無音
8. DAW音が少しだけマイクに漏れている
9. WAV尺と動画尺が0.5秒違う
10. 縦動画と横動画が混在
11. iPhone HDR動画
12. 4K動画
13. 途中でテンポチェンジ
14. 弱起の曲
15. ドラムだけクリックに近い強い波形

## 16. Cloud Agent向け初期指示の核

次に作るべき指示書は、まずこれ。

### Phase 0.5A：Import-first Export PoC 指示書

目的：

既存動画と完成WAVを読み込み、動画側とWAV側の曲開始基準点を指定し、完成WAVつきの1画面動画を書き出せることを検証する。

重要要件：

- Swift / SwiftUI / AVFoundation を使う
- FFmpegKitには依存しない
- 動画をカメラロールから読み込める
- WAVを読み込める
- 動画側の曲開始位置 `songStartRawSec` を手動指定できる
- WAV側の曲開始位置 `songStartAudioSec` を手動指定できる
- `selectedRawStartSec` / `selectedRawEndSec` を指定できる
- カメラ音声をミュートできる
- 完成WAVを本番音声として差し込める
- 1画面MP4として書き出せる
- 編集は非破壊で行う

## 17. 最終まとめ

TakeLayerは、単なる録画アプリではない。

DAW制作と動画投稿の間にある、面倒で地味で、でも絶対必要な同期・整理・書き出し作業を消すアプリ。

最重要の設計判断はこれ。

1. `songStartRawSec` を中核にする
2. `songStartAudioSec` を中核にする
3. 録画開始・曲開始・発音開始・切り出し開始を分ける
4. 完成WAVをReference Performance Anchorにする
5. 自動トリムは無音カットではなく曲尺ウィンドウ探索
6. 手動補正UIを主機能にする
7. iOSネイティブ優先
8. FFmpegKit中核依存は避ける
9. まずImport-first Export PoCから始める
10. 将来的に分割・制作過程風・Natural Syncへ育てる
