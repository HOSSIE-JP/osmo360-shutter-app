# 検証記録

## 自動検証

2026-09-26、Flutter 3.35.5 / Ubuntu 24.04、コミット `b782c13708eed11b8465b069abcd2cdd5d1aec33` で以下が成功しています。

| 検証 | 結果 |
|---|---|
| Flutter静的解析 | 問題なし |
| Flutterテスト | 21件成功 |
| Web端末ブリッジのNodeテスト | 7件成功 |
| Flutter Web release生成 | 成功 |
| GitHub Pagesデプロイ | 成功 |
| Android debug APK生成 | 成功 |

- [Web検証・公開ログ](https://github.com/HOSSIE-JP/osmo360-shutter-app/actions/runs/36265339421)
- [Androidビルド・APK](https://github.com/HOSSIE-JP/osmo360-shutter-app/actions/runs/36265339432)
- [公開PWA](https://hossie-jp.github.io/osmo360-shutter-app/)

FlutterテストはCRC・フレーム分割、GPS時刻と欠測、安全な撮影判定、プロジェクト分離、保存中の停止、異常終了復旧、APIキーを含まない書き出し、390×844 / 1366×900の画面構成を検証しています。

さらに地図HTMLへのナビゲーションをService Workerが正しく返す修正と4件の回帰テストを追加しています。最新ワークフローはNodeテスト計11件に加え、公開後にHTTPS経由でHTML、manifest、192/512pxアイコン、Service Worker、Flutter本体、地図HTMLを取得して検証します。最新コミットの実行結果は[Actions](https://github.com/HOSSIE-JP/osmo360-shutter-app/actions/workflows/pages.yml)を参照してください。

## 未検証

作業環境との接続断により、公開URLでのブラウザー操作・スクリーンショット確認は完了していません。テスト内のレイアウト確認と、実ブラウザーでの表示確認は区別しています。

実機Bluetooth接続・撮影・画像の保存、GPSのEXIF埋め込み、端末の歩数／静止検出、Google Mapsの有効なAPIキーによる表示、PWAの実端末インストール、オフライン起動の実機操作は未検証です。実機での確認は [HARDWARE_TESTS.md](HARDWARE_TESTS.md) にまとめています。実用化に向けた評価版としてご利用ください。
