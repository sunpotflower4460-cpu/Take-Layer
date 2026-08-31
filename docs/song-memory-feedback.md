# Song Memory & Feedback Learning

## 1. Goal

TakeLayerは、ユーザーが一度入力した曲情報と、一度「良い」と評価した編集判断を次回以降の提案へ活かす。

目的は、一般的な動画編集AIではなく、**そのユーザー・その曲・その演奏スタイルを徐々に理解する専属編集AI**になること。

## 2. Memory scopes

学習は混ぜずに階層化する。

### Song-specific memory

その曲だけに効く記憶。

例:

- Re:tripではサビ頭から始める案が好まれる
- Re:tripは小さめの歌詞が好まれる
- Aquariumは長いslow zoomが好まれる

### Artist / project memory

特定アーティスト、ユニット、企画に効く記憶。

例:

- しののめむすびでは暖かい自然色を好む
- ソロ弾き語りでは過剰なトランジションを避ける

### User-wide preference

多くの曲で繰り返し確認された傾向。

例:

- 字幕は下寄り
- titleは短時間
- zoomは弱め
- rawな質感を残す

## 3. What counts as feedback

単純な星評価だけでなく、ユーザー操作そのものを学習信号にする。

### Strong positive

- Proposalを承認した
- 「良い」「これが好き」と明示評価した
- ほぼ無修正で書き出した

### Strong negative

- Proposalを明示的に却下した
- 「この編集は嫌い」と評価した

### Edit-delta signal

AI案から人間が変更した差分。

例:

```text
subtitle.fontSize 54 → 42
zoom.scale 1.10 → 1.04
hook.start 42.0 → 38.4
color.saturation +15 → +3
```

この差分は非常に重要な教師信号。

「採用されたか」だけでなく、**採用するために何を直したか**を保存する。

## 4. Do not overlearn

1回の承認を「普遍的な好み」と断定しない。

各Preferenceには次を持つ。

- scope
- evidenceCount
- positiveWeight
- negativeWeight
- confidence
- lastObservedAt
- context tags

例:

```text
Preference:
  rule: zoom_intensity <= low
  scope: acoustic_solo
  evidenceCount: 8
  confidence: 0.86
```

1本だけなら弱い参考。

複数曲で繰り返されればUser-wide preferenceへ昇格できる。

## 5. Context matters

同じユーザーでも、すべての動画で同じ編集が良いとは限らない。

最低限、次のContextを持つ。

- songId
- arrangementType
- performanceType
- platform
- aspectRatio
- proposalStyle
- sectionType
- tempo / energy band
- camera setup
- indoor / outdoor hint

例:

「強いzoomが嫌い」ではなく、

```text
acoustic_solo + natural style では強いzoomを避ける
```

という形で覚える。

## 6. Approval loop

```text
AI proposes A / B / C
        ↓
User selects B
        ↓
User adjusts B
        ↓
Approved final edit
        ↓
Diff(AI_B, Final_B)
        ↓
Preference Signals
        ↓
Song Memory / User Preference更新
        ↓
Next proposal generation
```

## 7. Proposal diversity and learning

毎回ほぼ同じ案を3つ出すと学習にならない。

Proposal間には意図的に差を作る。

例:

- A: 最も既存Preferenceに近い安全案
- B: 少し新しい仮説
- C: 明確に異なるが曲に合う挑戦案

これにより、ユーザーの好みを固定化しすぎず、より良い表現の探索を続けられる。

## 8. Same-song recognition

Song Memory適用前に同一曲判定を行う。

同じSongと同じRecording/Arrangementを区別する。

例:

```text
Song: Re:trip
  ├─ Studio Master 2026
  ├─ Acoustic Solo
  ├─ Shinonome Musubi Live
  └─ Alternate Tempo Version
```

判定Evidence:

- fingerprint
- chroma
- melody contour
- lyrics match
- duration
- master relation
- metadata

低confidenceなら必ずユーザー確認へ戻す。

## 9. Formal information precedence

同じフィールドに複数情報源がある場合の優先順位。

```text
1. User-confirmed value
2. Previously confirmed Song Memory
3. Trusted imported metadata
4. Analysis estimate
5. Unknown
```

ユーザーが確定した曲名や歌詞を、外部検索結果で勝手に上書きしない。

## 10. Explainable recommendations

Preferenceを適用したときは、将来的に理由を表示できるようにする。

例:

```text
歌詞を小さめにしました。
理由: この曲で過去3回、小さめ字幕の編集を承認しています。
```

または、

```text
今回は過去の好みと違い、サビで少し強いzoom案も1本含めました。
```

AIが「記憶を根拠にしている」のか「新しい仮説を試している」のかを区別する。

## 11. Privacy and control

Preference Memoryはユーザーが確認・修正・削除できるようにする。

例:

- この曲について覚えていること
- 私の編集の好み
- このPreferenceを忘れる
- この曲のMemoryをリセット

暗黙学習だけで取り返しがつかない状態にしない。

## 12. Recommended first implementation

Preference Learningは最初から機械学習モデルの再学習を行う必要はない。

最初は構造化ルール + 重み付き履歴で十分。

```text
approvedProposalStyle counts
manual edit deltas
rejected feature counts
song-specific defaults
user-wide defaults
```

データが蓄積してから、ranking modelやembedding-based retrievalへ進める。

この順番の方が、挙動を説明しやすくデバッグもしやすい。
