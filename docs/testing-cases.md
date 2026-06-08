# Testing Cases

TakeLayer should plan test fixtures around cases that protect the core design: song-start anchors, completed-WAV reference audio, non-destructive trim, and no automatic removal of musical silence.

Initial cases:

1. 曲頭から全員鳴る。
2. ボーカルが40秒後に入る。
3. ギターがサビまで入らない。
4. 8秒ブレイクがある。
5. 20秒失敗テイク後に本テイク。
6. 本テイク後に会話。
7. カメラ音声がほぼ無音。
8. DAW音が少しだけマイクに漏れている。
9. WAV尺と動画尺が0.5秒違う。
10. 縦動画と横動画が混在。
11. iPhone HDR動画。
12. 4K動画。
13. 途中でテンポチェンジ。
14. 弱起の曲。
15. ドラムだけクリックに近い強い波形。

These cases should be used from early PoC work onward. Cases 2, 3, and 4 are especially important because they prevent confusing `firstSoundRawSec` or silence with `songStartRawSec`.
