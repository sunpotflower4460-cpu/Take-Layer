# TakeLayer AI Music Video Director Vision

## 1. Purpose

TakeLayerの将来像は、単なる同期・書き出しアプリではなく、**演奏素材を理解し、完成度の高いショート動画案を複数提案する音楽家専用AI Director**へ拡張すること。

ただし、既存のTakeLayer Coreを置き換えない。

```text
TakeLayer Core
= 正確な時間軸 / 同期 / 非破壊編集 / 完成WAV基準 / 安全な書き出し

AI Director
= 曲理解 / 見せ場選定 / 歌詞 / crop / title / effect / proposal / preference learning
```

AIが編集意図を考え、実際の時間・座標・crop・字幕・音量・色・トランジションは可能な限り決定論的なEditing Planへ落としてレンダリングする。

## 2. Primary UX: アコギ弾き語り

最重要ユースケースは次の体験。

1. ユーザーが弾き語り動画を投入する。
2. 必要なら完成WAVを投入する。
3. 曲名・アーティスト・オリジナル/既存曲・任意情報だけ入力する。
4. TakeLayerが同じ曲の過去情報を検索する。
5. 曲が既知なら保存済みSong Profileを提案する。
6. 未知または既存曲なら外部メタデータ候補も検索する。
7. 音声・映像・歌詞・曲構造を解析する。
8. AI Directorがショート動画の編集案を複数作る。
9. ユーザーはプレビュー比較し、1案を選ぶ。
10. 最後の微調整だけ行う。
11. 承認した編集と修正差分をPreference Memoryへ保存する。

目標は、最終的にユーザー操作を次まで減らすこと。

```text
動画を入れる
→ 曲候補を確認
→ 3〜5案を見る
→ 微調整
→ 承認
```

## 3. Proposal-first principle

既存TakeLayerの「候補提示 + 手動確認」をAI Directorでも守る。

AIは最初から1本を正解として押し付けない。

例:

- Natural Performance
- Cinematic
- Lyric Focus
- Social Hook
- Minimal / Raw

同じ素材から3〜5案を作り、ユーザーの比較判断を学習信号にする。

## 4. Song Resolver

動画投入時に、まず「これは何の曲か」を解決する。

### 4.1 Evidence

単一手法に依存せず、次を組み合わせる。

- Audio fingerprint
- Chroma / harmonic similarity
- Melody / pitch contour
- Lyrics alignment / speech-to-text hint
- Duration
- Existing master WAV similarity
- User-entered title / artist
- Previously imported assets
- Optional external metadata candidates

### 4.2 Confidence policy

例:

```text
>= 0.90  高信頼: 保存済みSong Profileを強く提案
0.65-0.90 中信頼: 候補を並べてユーザー確認
< 0.65    未確定: 新規Songとして扱うか検索候補を提示
```

自動採用の閾値は高く保つ。

## 5. Song Profile / Song Memory

曲単位の永続記憶を持つ。

保存候補:

- canonical title
- artist / unit
- original / cover
- aliases
- ISRC等の識別子
- BPM / key / tuning / frequency note
- formal lyrics supplied by the user
- song sections
- known chorus / hook regions
- artwork / metadata references
- preferred visual mood
- subtitle preferences
- approved titles
- previously approved edit proposals
- rejected patterns and reasons
- master WAV fingerprints
- live / acoustic / studio asset relations

同じ曲でもスタジオ版、ライブ版、弾き語り版、テンポ違いがあり得るため、SongとRecording/Arrangementは分けて扱う。

## 6. Existing-song metadata

既存曲の場合はMetadata Provider Adapterを通じて情報候補を取得する。

候補Provider:

- MusicBrainz
- Apple Music catalog
- その他、利用条件を満たす音楽メタデータサービス

原則:

- 外部情報は「候補」であり正本ではない。
- タイトル、アーティスト、リリース、ISRC等を照合する。
- ライセンスや利用規約により、音源・歌詞全文・画像を自由に再利用できるとは仮定しない。
- ユーザー自身が登録したオリジナル曲情報を最優先する。

## 7. Lyrics pipeline

歌詞精度を最大化するため、優先順位を固定する。

```text
1. Song Memory内のユーザー確認済み正式歌詞
2. 今回ユーザーが入力した歌詞
3. 正規に利用可能な歌詞ソース
4. 音声からの自動推定
```

正式歌詞が存在する場合、AIは全文を書き起こすより、**既知歌詞のどの語を現在歌っているかをアラインする**ことを優先する。

Lyrics Alignmentは単語/行ごとのtimestampとconfidenceを保持する。

## 8. Analysis pipeline

```text
Upload
  ↓
Media inspection
  ↓
Song Resolver
  ↓
Song Memory / Metadata candidate retrieval
  ↓
TakeLayer Core synchronization
  ↓
Audio analysis
  ├─ sections
  ├─ onset / beat
  ├─ energy
  ├─ vocal activity
  ├─ melody / harmony
  └─ highlight candidates
  ↓
Video analysis
  ├─ face / performer tracking
  ├─ framing
  ├─ motion
  ├─ blur / shake
  ├─ exposure
  └─ usable crop areas
  ↓
Lyrics alignment
  ↓
AI Director
  ↓
Editing Plan × 3〜5
  ↓
Deterministic Renderer
  ↓
Quality Gate
  ↓
Preview proposals
  ↓
Human adjustment / approval
  ↓
Preference Memory
```

## 9. AI Director responsibilities

AI Directorは「何をすべきか」を決める。

- ショートで使う範囲
- 冒頭フック位置
- どの歌詞を見せるか
- title / artist表示
- crop strategy
- performer tracking strategy
- zoom / pan intensity
- sectionごとの演出
- color mood
- transition frequency
- effect restraint
- proposal diversity

重要なのは、**何もしない判断も演出として扱うこと**。

弾き語りでは過剰なzoom、transition、字幕、光エフェクトを避け、音楽を邪魔しないことを品質基準に含める。

## 10. Editing Plan

生成AIから直接動画を書き出させず、編集判断を中間表現へ落とす。

例:

```json
{
  "trim": { "startSec": 38.2, "endSec": 66.4 },
  "canvas": "9:16",
  "crop": { "mode": "performer_track", "strength": 0.25 },
  "title": { "text": "Re:trip", "startSec": 0.0, "endSec": 1.8 },
  "lyrics": { "style": "minimal", "maxLines": 2 },
  "cameraMoves": [
    { "startSec": 6.0, "endSec": 14.0, "type": "slow_zoom", "scaleTo": 1.04 }
  ],
  "effects": { "intensity": "low" }
}
```

この方式なら、

- 再現性
- Undo
- 微調整
- A/B比較
- 学習
- 品質検査

を行いやすい。

## 11. Quality Gate

自動生成後に最低限の機械検査を行う。

- 字幕がsafe area外へ出ていない
- 顔やギターの重要部分をcropしていない
- 歌詞timestampの低confidence箇所を警告
- 音声同期誤差
- 急激すぎるcrop movement
- 不要なblack frame
- title / lyric collision
- 過剰なcut frequency
- target platformのduration / aspect ratio
- export integrity

Quality Gateを通らない案は、ユーザーに出す前に再生成または警告する。

## 12. Multi-part extension

既存TakeLayerの複数パート同期はそのままAI Directorへ拡張できる。

各瞬間のPart Salienceを推定し、前面へ出す候補を決める。

```text
Part Salience
≈ onset + energy change + spectral novelty + melodic activity
  + section importance + performer motion + musical role
```

ただし周波数だけで判断しない。

ギターソロ、ドラムフィル、ボーカル開始など、音楽的イベントを考慮する。

## 13. Non-goal boundary

この文書は**将来設計**であり、現在のPhase 0 / 0.5Aの実装範囲を拡大しない。

現在のTakeLayer Coreの検証を先に成功させ、その上にAI Directorを積む。

同期の正確さと非破壊性を犠牲にしてAI機能を先行実装しない。
